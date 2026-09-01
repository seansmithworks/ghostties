#import "CEFBridge.h"
#import <AppKit/AppKit.h>
#include <atomic>

#if DEBUG
#import <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>
#include <signal.h>
#include <execinfo.h>
#include <stdlib.h>
#endif

#if __has_include("include/cef_app.h")
#define GHOSTTIES_CEF_AVAILABLE 1
#import "include/cef_app.h"
#import "include/cef_browser.h"
#import "include/cef_browser_process_handler.h"
#import "include/wrapper/cef_helpers.h"
#import "include/wrapper/cef_library_loader.h"
#else
#define GHOSTTIES_CEF_AVAILABLE 0
#endif

// ---------------------------------------------------------------------------
// Static state
// ---------------------------------------------------------------------------

static BOOL _isInitialized = NO;
static NSTimer *_messageLoopTimer = nil;

// ---------------------------------------------------------------------------
// CefApp implementation for external message pump integration
// ---------------------------------------------------------------------------

#if GHOSTTIES_CEF_AVAILABLE

/// Handles scheduling of message pump work from CEF's internal threads.
/// When CEF needs processing time, it calls OnScheduleMessagePumpWork
/// which dispatches to the main thread for our timer to handle.
class GhosttiesBrowserProcessHandler : public CefBrowserProcessHandler {
public:
    void OnScheduleMessagePumpWork(int64_t delay_ms) override {
        // Coalesce rapid zero-delay callbacks to avoid flooding the main queue
        // (CefDoMessageLoopWork can re-schedule with delay=0, creating a spin loop
        // that starves AppKit and causes the beach ball).
        if (delay_ms <= 0) {
            if (!work_pending_.exchange(true)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    work_pending_ = false;
                    CefDoMessageLoopWork();
                });
            }
        } else {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{
                    CefDoMessageLoopWork();
                });
        }
    }

private:
    std::atomic<bool> work_pending_{false};
    IMPLEMENT_REFCOUNTING(GhosttiesBrowserProcessHandler);
};

class GhosttiesApp : public CefApp {
public:
    GhosttiesApp() : browser_handler_(new GhosttiesBrowserProcessHandler()) {}

    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return browser_handler_;
    }

private:
    CefRefPtr<GhosttiesBrowserProcessHandler> browser_handler_;
    IMPLEMENT_REFCOUNTING(GhosttiesApp);
};

#endif // GHOSTTIES_CEF_AVAILABLE

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

#if DEBUG
/// Logs the on-disk singleton-lock state relative to the current host, to
/// distinguish a stale-lock-across-a-hostname-flip shutdown (see
/// reference_dev-builds-share-a-bundle-id / hypothesis in the CEF shutdown
/// investigation) from any other cause. Debug-only, [CEFDiag]-tagged.
static void GhosttiesLogSingletonLockState(NSString *cacheDir) {
    NSString *lockPath = [cacheDir stringByAppendingPathComponent:@"SingletonLock"];

    char hostnameBuf[256] = {0};
    gethostname(hostnameBuf, sizeof(hostnameBuf));
    NSString *posixHostname = [NSString stringWithUTF8String:hostnameBuf];

    NSString *bonjourLocalHostName = (__bridge_transfer NSString *)SCDynamicStoreCopyLocalHostName(NULL);

    const char *cLockPath = [lockPath fileSystemRepresentation];
    char linkTarget[PATH_MAX] = {0};
    ssize_t linkLen = readlink(cLockPath, linkTarget, sizeof(linkTarget) - 1);
    if (linkLen < 0) {
        NSLog(@"[CEFDiag] SingletonLock: absent or not a symlink at %@ (errno=%d %s). "
              @"posixHostname=%@ bonjourLocalHostName=%@",
              lockPath, errno, strerror(errno), posixHostname, bonjourLocalHostName);
        return;
    }
    linkTarget[linkLen] = '\0';
    NSString *target = [NSString stringWithUTF8String:linkTarget];

    // Lock target format is "<hostname>-<pid>" — split on the last '-'.
    NSRange dashRange = [target rangeOfString:@"-" options:NSBackwardsSearch];
    NSString *lockHostname = (dashRange.location != NSNotFound)
        ? [target substringToIndex:dashRange.location]
        : nil;
    NSString *lockPidString = (dashRange.location != NSNotFound)
        ? [target substringFromIndex:dashRange.location + 1]
        : nil;
    pid_t lockPid = lockPidString ? (pid_t)[lockPidString integerValue] : 0;

    BOOL pidAlive = NO;
    if (lockPid > 0) {
        pidAlive = (kill(lockPid, 0) == 0);
    }

    NSLog(@"[CEFDiag] SingletonLock target=%@ (lockHostname=%@ lockPid=%d pidAlive=%@) "
          @"posixHostname=%@ bonjourLocalHostName=%@ hostnameMatch=%@",
          target, lockHostname, lockPid, pidAlive ? @"YES" : @"NO",
          posixHostname, bonjourLocalHostName,
          ([lockHostname isEqualToString:posixHostname] ||
           [lockHostname isEqualToString:bonjourLocalHostName]) ? @"YES" : @"NO");
}

/// Logs a symbolized backtrace tagged [CEFDiag], one frame per line so it
/// survives the unified log. Called from both the atexit handler and the
/// signal handlers below — the goal is naming whatever calls exit() (or
/// crashes) beneath AppKit during the browser-open shutdown.
static void GhosttiesLogBacktrace(const char *reason) {
    void *frames[64];
    int count = backtrace(frames, 64);
    char **symbols = backtrace_symbols(frames, count);
    NSLog(@"[CEFDiag] %s — backtrace (%d frames):", reason, count);
    if (symbols) {
        for (int i = 0; i < count; i++) {
            NSLog(@"[CEFDiag]   #%d %s", i, symbols[i]);
        }
        free(symbols);
    } else {
        NSLog(@"[CEFDiag]   (backtrace_symbols failed, errno=%d %s)", errno, strerror(errno));
    }
}

/// Fires on any exit() (including implicit exit at the end of main, which
/// won't apply here, and any explicit exit()/abort() call reachable through
/// libc's atexit machinery). Does NOT fire for _exit()/_Exit(), which is why
/// the signal handlers below exist as a second net.
static void GhosttiesAtExitHandler(void) {
    GhosttiesLogBacktrace("atexit fired");
}

/// Logs a backtrace then restores default disposition and re-raises, so the
/// crash still produces its normal report/termination — this only adds a
/// log line ahead of it, it does not change what happens to the process.
static void GhosttiesSignalHandler(int signo) {
    // NSLog and backtrace_symbols are not async-signal-safe. This is a
    // Debug-only diagnostic build where "some evidence, maybe corrupted" beats
    // "no evidence" — acceptable tradeoff here, not for shipping code.
    GhosttiesLogBacktrace("signal handler fired");
    signal(signo, SIG_DFL);
    raise(signo);
}

/// Installs both nets as early as possible — see +load below, which runs at
/// image-load time, before CEF (or anything else in this process) is touched.
static void GhosttiesInstallExitDiagnostics(void) {
    atexit(GhosttiesAtExitHandler);
    signal(SIGABRT, GhosttiesSignalHandler);
    signal(SIGSEGV, GhosttiesSignalHandler);
    signal(SIGILL, GhosttiesSignalHandler);
    signal(SIGBUS, GhosttiesSignalHandler);
    signal(SIGTRAP, GhosttiesSignalHandler);
    NSLog(@"[CEFDiag] Exit diagnostics installed (atexit + signal handlers).");
}
#endif // DEBUG

@interface CEFBridgeManager ()
+ (void)_messageLoopTick:(NSTimer *)timer;
+ (void)_appWillTerminate:(NSNotification *)note;
@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation CEFBridgeManager

#pragma mark - Diagnostics installation

+ (void)load {
    // +load runs at image-load time, before main() — before AppDelegate,
    // before CEF, before anything else in this process. This is the
    // earliest hook available for installing the exit/crash diagnostics
    // below.
#if DEBUG
    GhosttiesInstallExitDiagnostics();
#endif
}

#pragma mark - Properties

+ (BOOL)isInitialized {
    return _isInitialized;
}

#pragma mark - Lifecycle

+ (void)initializeIfNeeded {
    if (_isInitialized) return;

    NSAssert([NSThread isMainThread],
             @"CEFBridgeManager.initializeIfNeeded must be called on the main thread");

#if GHOSTTIES_CEF_AVAILABLE
    // ---- Load framework dynamically ------------------------------------
    static CefScopedLibraryLoader sLibraryLoader;
    static BOOL sLibraryLoaded = NO;
    if (!sLibraryLoaded) {
        if (!sLibraryLoader.LoadInMain()) {
            NSLog(@"[CEFBridge] Failed to load CEF framework.");
            return;
        }
        sLibraryLoaded = YES;
    }

    // ---- Framework paths ------------------------------------------------

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *frameworkPath = [mainBundle.privateFrameworksPath
        stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
    NSString *helperPath = [[mainBundle.privateFrameworksPath
        stringByAppendingPathComponent:@"Ghostties Helper.app/Contents/MacOS/Ghostties Helper"]
        stringByStandardizingPath];

    // ---- CefSettings ----------------------------------------------------

    CefSettings settings;
    settings.no_sandbox = true;
    settings.external_message_pump = true;

    CefString(&settings.framework_dir_path) = [frameworkPath UTF8String];
    CefString(&settings.browser_subprocess_path) = [helperPath UTF8String];

    // Cache directory — required by CEF for subprocess data exchange.
    // Use ~/Library/Application Support/<bundleIdentifier>/CEF/ so dev and
    // release builds don't share a cache (bundle IDs differ by `.dev` suffix).
    NSArray<NSString *> *appSupportPaths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupportBase = appSupportPaths.firstObject
        ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.seansmithdesign.ghostties";
    NSString *cacheDir = [[appSupportBase
        stringByAppendingPathComponent:bundleId]
        stringByAppendingPathComponent:@"CEF"];
    NSError *cacheDirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:cacheDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&cacheDirError]) {
        NSLog(@"[CEFBridge] Failed to create cache directory %@: %@",
              cacheDir, cacheDirError.localizedDescription);
    }
    CefString(&settings.root_cache_path) = [cacheDir UTF8String];
    CefString(&settings.cache_path) = [cacheDir UTF8String];
    CefString(&settings.locale) = "en-US";

    // CEF's own log file — stored alongside the cache.
    NSString *logFile = [cacheDir stringByAppendingPathComponent:@"ghostties-cef-internal.log"];
    CefString(&settings.log_file) = [logFile UTF8String];
#if DEBUG
    settings.log_severity = LOGSEVERITY_VERBOSE;
#else
    settings.log_severity = LOGSEVERITY_WARNING;
#endif

    settings.remote_debugging_port = 0;

    // ---- Main args ------------------------------------------------------

    static const char *fakeArgv[] = {
        "Ghostties",
        "--use-mock-keychain",
        nullptr
    };
    CefMainArgs mainArgs(2, const_cast<char**>(fakeArgv));

    // ---- Initialize with our CefApp ------------------------------------
    // GhosttiesApp provides the BrowserProcessHandler which implements
    // OnScheduleMessagePumpWork for external_message_pump integration.

#if DEBUG
    GhosttiesLogSingletonLockState(cacheDir);
#endif

    CefRefPtr<GhosttiesApp> app(new GhosttiesApp());
    bool success = CefInitialize(mainArgs, settings, app, nullptr);
#if DEBUG
    NSLog(@"[CEFDiag] CefInitialize returned %@", success ? @"true" : @"false");
#endif
    if (!success) {
        NSLog(@"[CEFBridge] CefInitialize failed.");
        return;
    }

    // ---- Backup timer (30 Hz) ------------------------------------------
    // The primary message pump is driven by OnScheduleMessagePumpWork above.
    // This timer is a safety net to ensure events are processed
    // even if a callback is missed.

    _messageLoopTimer = [NSTimer timerWithTimeInterval:1.0/30.0
                                                target:self
                                              selector:@selector(_messageLoopTick:)
                                              userInfo:nil
                                               repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_messageLoopTimer
                              forMode:NSRunLoopCommonModes];

    // ---- App termination observer --------------------------------------

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];

    _isInitialized = YES;
    NSLog(@"[CEFBridge] CEF initialized.");

#else
    NSLog(@"[CEFBridge] CEF headers not available — running in stub mode.");
#endif
}

+ (void)shutdown {
    if (!_isInitialized) return;

    NSAssert([NSThread isMainThread],
             @"CEFBridgeManager.shutdown must be called on the main thread");

    [_messageLoopTimer invalidate];
    _messageLoopTimer = nil;

#if GHOSTTIES_CEF_AVAILABLE
    CefShutdown();
    NSLog(@"[CEFBridge] CEF shut down.");
#endif

    _isInitialized = NO;
}

#pragma mark - Private

+ (void)_messageLoopTick:(NSTimer *)timer {
#if GHOSTTIES_CEF_AVAILABLE
    CefDoMessageLoopWork();
#endif
}

+ (void)_appWillTerminate:(NSNotification *)note {
#if DEBUG
    NSLog(@"[CEFDiag] NSApplicationWillTerminateNotification fired at %@",
          [NSDate date]);
#endif
    [self shutdown];
}

@end
