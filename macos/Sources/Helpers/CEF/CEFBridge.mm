#import "CEFBridge.h"
#import <AppKit/AppKit.h>
#include <atomic>
#import <os/log.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>

#if DEBUG
#include <execinfo.h>
#endif

#if __has_include("include/cef_app.h")
#define GHOSTTIES_CEF_AVAILABLE 1
#import "include/cef_app.h"
#import "include/cef_browser.h"
#import "include/cef_browser_process_handler.h"
#import "include/cef_version.h"
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
static BOOL _priorLaunchLeftUnclearedAttempt = NO;

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

/// Runtime gate for `[CEFDiag]` probes. Was `#if DEBUG`; moved to a runtime
/// check so these probes can be turned on in a Release build (via
/// `GHOSTTIES_CEF_DIAG=1`) without a recompile. The `atexit`/signal-handler
/// diagnostics below stay compile-time Debug-only — those are not safe to
/// ship into Release (see GhosttiesInstallExitDiagnostics).
static BOOL GhosttiesCEFDiagEnabled(void) {
    const char *value = getenv("GHOSTTIES_CEF_DIAG");
    return value != NULL && value[0] == '1' && value[1] == '\0';
}

/// Runtime gate for `GHOSTTIES_CEF_LOG_VERBOSE=1`.
static BOOL GhosttiesCEFLogVerboseEnabled(void) {
    const char *value = getenv("GHOSTTIES_CEF_LOG_VERBOSE");
    return value != NULL && value[0] == '1' && value[1] == '\0';
}

/// Logs the on-disk singleton-lock state relative to the current host, to
/// distinguish a stale-lock-across-a-hostname-flip shutdown (see
/// reference_dev-builds-share-a-bundle-id / hypothesis in the CEF shutdown
/// investigation) from any other cause. `[CEFDiag]`-tagged, gated on
/// `GhosttiesCEFDiagEnabled()` so it survives into Release behind the env
/// var.
static void GhosttiesLogSingletonLockState(NSString *cacheDir) {
    if (!GhosttiesCEFDiagEnabled()) return;

    NSString *lockPath = [cacheDir stringByAppendingPathComponent:@"SingletonLock"];

    char hostnameBuf[256] = {0};
    gethostname(hostnameBuf, sizeof(hostnameBuf));
    NSString *posixHostname = [NSString stringWithUTF8String:hostnameBuf];

    NSString *bonjourLocalHostName = (__bridge_transfer NSString *)SCDynamicStoreCopyLocalHostName(NULL);

    const char *cLockPath = [lockPath fileSystemRepresentation];
    char linkTarget[PATH_MAX] = {0};
    ssize_t linkLen = readlink(cLockPath, linkTarget, sizeof(linkTarget) - 1);
    if (linkLen < 0) {
        // NSLog does not honor the `{public}` privacy annotation (it is only
        // meaningful to os_log()/os_trace() — clang warns on this at the
        // NSLog call site, and the unified log silently corrupts the
        // argument decode rather than un-redacting it). os_log() is the
        // mechanism that actually makes these values visible.
        os_log(OS_LOG_DEFAULT,
               "[CEFDiag] SingletonLock: absent or not a symlink at %{public}@ (errno=%d %{public}s). "
               "posixHostname=%{public}@ bonjourLocalHostName=%{public}@",
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

    os_log(OS_LOG_DEFAULT,
           "[CEFDiag] SingletonLock target=%{public}@ (lockHostname=%{public}@ lockPid=%d pidAlive=%{public}@) "
           "posixHostname=%{public}@ bonjourLocalHostName=%{public}@ hostnameMatch=%{public}@",
           target, lockHostname, lockPid, pidAlive ? @"YES" : @"NO",
           posixHostname, bonjourLocalHostName,
           ([lockHostname isEqualToString:posixHostname] ||
            [lockHostname isEqualToString:bonjourLocalHostName]) ? @"YES" : @"NO");
}

#if DEBUG
/// Logs a symbolized backtrace tagged [CEFDiag], one frame per line so it
/// survives the unified log. Called from both the atexit handler and the
/// signal handlers below — the goal is naming whatever calls exit() (or
/// crashes) beneath AppKit during the browser-open shutdown. Debug-only:
/// these handlers install atexit()/signal() hooks that stay compile-time
/// gated even though the [CEFDiag] logging above is now runtime-gated.
static void GhosttiesLogBacktrace(const char *reason) {
    void *frames[64];
    int count = backtrace(frames, 64);
    char **symbols = backtrace_symbols(frames, count);
    os_log(OS_LOG_DEFAULT, "[CEFDiag] %{public}s — backtrace (%d frames):", reason, count);
    if (symbols) {
        for (int i = 0; i < count; i++) {
            os_log(OS_LOG_DEFAULT, "[CEFDiag]   #%d %{public}s", i, symbols[i]);
        }
        free(symbols);
    } else {
        os_log(OS_LOG_DEFAULT, "[CEFDiag]   (backtrace_symbols failed, errno=%d %{public}s)", errno, strerror(errno));
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
    // os_log() and backtrace_symbols are not async-signal-safe. This is a
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
+ (NSString *)_appSupportBundleDirectory;
+ (NSString *)_iso8601Timestamp;
+ (nullable NSString *)_moveProfileAsideWithPrefix:(NSString *)prefix error:(NSError **)error;
+ (NSInteger)_recordedChromiumMajorVersionOrZero;
+ (void)_performDowngradeGuardIfNeeded;
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

+ (BOOL)priorLaunchLeftUnclearedAttempt {
    return _priorLaunchLeftUnclearedAttempt;
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
    NSString *cacheDir = [self cefProfileDirectoryPath];

    // Downgrade guard — must run before anything below touches cacheDir, so
    // a poisoned profile is moved aside before CEF ever opens it.
    [self _performDowngradeGuardIfNeeded];

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

    // GHOSTTIES_CEF_LOG_VERBOSE=1 forces verbose CEF/Chromium logging plus
    // targeted vmodule tracing for the shutdown/keep-alive paths implicated
    // in the profile-downgrade crash, independent of build configuration.
    BOOL cefLogVerbose = GhosttiesCEFLogVerboseEnabled();
    if (cefLogVerbose) {
        settings.log_severity = LOGSEVERITY_VERBOSE;
    }

    settings.remote_debugging_port = 0;

    // ---- Main args ------------------------------------------------------

    static const char *fakeArgvBase[] = {
        "Ghostties",
        "--use-mock-keychain",
        nullptr
    };
    static const char *fakeArgvVerbose[] = {
        "Ghostties",
        "--use-mock-keychain",
        "--vmodule=browser_shutdown=2,keep_alive_registry=2,browser_process_impl=2",
        nullptr
    };
    const char **fakeArgv = cefLogVerbose ? fakeArgvVerbose : fakeArgvBase;
    int fakeArgc = cefLogVerbose ? 3 : 2;
    CefMainArgs mainArgs(fakeArgc, const_cast<char**>(fakeArgv));

    // ---- Initialize with our CefApp ------------------------------------
    // GhosttiesApp provides the BrowserProcessHandler which implements
    // OnScheduleMessagePumpWork for external_message_pump integration.

    GhosttiesLogSingletonLockState(cacheDir);

    os_log(OS_LOG_DEFAULT, "[CEFBridge] Pre-CefInitialize: cacheDir=%{public}@ logFile=%{public}@ verbose=%{public}@",
           cacheDir, logFile, cefLogVerbose ? @"YES" : @"NO");
    CefRefPtr<GhosttiesApp> app(new GhosttiesApp());

    // Snapshot whether a PRIOR launch left the sentinel uncleared, before
    // this launch overwrites it below. The sentinel is now written before
    // CefInitialize (bracketing the whole init+create sequence, not just
    // CreateBrowser) — so by the time browser creation checks it, the file
    // would always exist as THIS launch's own in-flight attempt. Callers
    // must consult this snapshot, not the live file, to ask "did the
    // previous launch die".
    _priorLaunchLeftUnclearedAttempt = [self hasUnclearedBrowserOpenAttempt];
    [self recordBrowserOpenAttempt];

    bool success = CefInitialize(mainArgs, settings, app, nullptr);
    os_log(OS_LOG_DEFAULT, "[CEFBridge] CefInitialize returned %{public}@", success ? @"true" : @"false");
    if (!success) {
        NSLog(@"[CEFBridge] CefInitialize failed.");
        return;
    }

    // Alive-tick probes: log every 250ms for 3s after CefInitialize returns.
    // Each tick that actually runs is, by construction, proof the process
    // survived to that point — this is the window the profile-downgrade
    // crash (a deliberate ~0.4-0.65s post-init quit) falls inside.
    for (int tick = 1; tick <= 12; tick++) {
        int64_t delayMs = tick * 250;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayMs * NSEC_PER_MSEC),
                        dispatch_get_main_queue(), ^{
            os_log(OS_LOG_DEFAULT, "[CEFBridge] alive-tick t+%{public}lldms", (long long)delayMs);
        });
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

#pragma mark - Browser-open sentinel (crash recovery)

#if DEBUG
static NSString *_testOverrideAppSupportBundleDirectory = nil;

+ (nullable NSString *)testOverrideAppSupportBundleDirectory {
    return _testOverrideAppSupportBundleDirectory;
}

+ (void)setTestOverrideAppSupportBundleDirectory:(nullable NSString *)path {
    _testOverrideAppSupportBundleDirectory = [path copy];
}
#endif

+ (NSString *)_appSupportBundleDirectory {
#if DEBUG
    // See the header doc on `testOverrideAppSupportBundleDirectory` — this
    // MUST be checked first so tests never touch Sean's real Dev CEF
    // profile, which lives at this exact derived path.
    if (_testOverrideAppSupportBundleDirectory) {
        return _testOverrideAppSupportBundleDirectory;
    }
#endif
    // GHOSTTIES_CEF_APP_SUPPORT_DIR is a lab hatch, not a behavior change:
    // the CEF profile dir, the browser-open-attempt sentinel, and any future
    // stamp file all derive from this one path, so overriding it here moves
    // them together. Unset, this must resolve byte-identically to the
    // original derivation below.
    NSString *resolvedPath;
    const char *envOverride = getenv("GHOSTTIES_CEF_APP_SUPPORT_DIR");
    if (envOverride != NULL && envOverride[0] != '\0') {
        resolvedPath = [NSString stringWithUTF8String:envOverride];
    } else {
        NSArray<NSString *> *appSupportPaths = NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *appSupportBase = appSupportPaths.firstObject
            ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.seansmithdesign.ghostties";
        resolvedPath = [appSupportBase stringByAppendingPathComponent:bundleId];
    }

    // Log once per distinct resolved value — this is called from several
    // paths (profile dir, sentinel path, reset) and would otherwise spam.
    static NSString *loggedPath = nil;
    if (![loggedPath isEqualToString:resolvedPath]) {
        loggedPath = resolvedPath;
        os_log(OS_LOG_DEFAULT, "[CEFBridge] Resolved app-support base directory: %{public}@", resolvedPath);
    }
    return resolvedPath;
}

+ (NSString *)_iso8601Timestamp {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
    });
    return [formatter stringFromDate:[NSDate date]];
}

+ (NSString *)cefProfileDirectoryPath {
    return [[self _appSupportBundleDirectory] stringByAppendingPathComponent:@"CEF"];
}

+ (NSString *)browserOpenAttemptSentinelPath {
    // A SIBLING of CEF/, not inside it — a profile reset (rename CEF/
    // aside) must never also remove evidence that an attempt was in flight.
    return [[self _appSupportBundleDirectory] stringByAppendingPathComponent:@"browser-open-attempt"];
}

+ (void)recordBrowserOpenAttempt {
    NSString *path = [self browserOpenAttemptSentinelPath];
    NSString *parentDir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parentDir
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
    NSError *error = nil;
    if (![[self _iso8601Timestamp] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[CEFBridge] Failed to write browser-open-attempt sentinel: %@", error.localizedDescription);
    } else {
        os_log(OS_LOG_DEFAULT, "[CEFBridge] Wrote browser-open-attempt sentinel at %{public}@", path);
    }
}

+ (void)clearBrowserOpenAttempt {
    NSString *path = [self browserOpenAttemptSentinelPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSError *error = nil;
        if (![fm removeItemAtPath:path error:&error]) {
            NSLog(@"[CEFBridge] Failed to clear browser-open-attempt sentinel: %@", error.localizedDescription);
        } else {
            os_log(OS_LOG_DEFAULT, "[CEFBridge] Cleared browser-open-attempt sentinel at %{public}@", path);
        }
    }
}

+ (BOOL)hasUnclearedBrowserOpenAttempt {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self browserOpenAttemptSentinelPath]];
}

+ (nullable NSString *)_moveProfileAsideWithPrefix:(NSString *)prefix error:(NSError **)error {
    NSString *profilePath = [self cefProfileDirectoryPath];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:profilePath]) {
        // Nothing to move aside — just ensure a fresh directory exists.
        [fm createDirectoryAtPath:profilePath withIntermediateDirectories:YES attributes:nil error:error];
        return nil;
    }

    // Sanitize the timestamp for use in a path component (colons are legal
    // on APFS but Finder mangles their display; avoid the confusion).
    NSString *sanitizedTimestamp = [[self _iso8601Timestamp]
        stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *movedPath = [[profilePath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix, sanitizedTimestamp]];

    if (![fm moveItemAtPath:profilePath toPath:movedPath error:error]) {
        return nil;
    }

    [fm createDirectoryAtPath:profilePath withIntermediateDirectories:YES attributes:nil error:error];
    return movedPath;
}

+ (nullable NSString *)resetProfileDirectoryPreservingDataError:(NSError **)error {
    return [self _moveProfileAsideWithPrefix:@"CEF-broken" error:error];
}

#pragma mark - Downgrade guard (Chromium major-version stamp)

+ (NSString *)chromiumVersionStampPath {
    return [[self _appSupportBundleDirectory] stringByAppendingPathComponent:@"cef-profile-chromium-version"];
}

+ (void)recordChromiumVersionStamp {
#if GHOSTTIES_CEF_AVAILABLE
    NSString *path = [self chromiumVersionStampPath];
    NSString *parentDir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parentDir
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
    NSString *contents = [NSString stringWithFormat:@"%d", CHROME_VERSION_MAJOR];
    NSError *error = nil;
    if (![contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[CEFBridge] Failed to write Chromium version stamp: %@", error.localizedDescription);
    } else {
        os_log(OS_LOG_DEFAULT, "[CEFBridge] Wrote Chromium version stamp (%d) at %{public}@",
               CHROME_VERSION_MAJOR, path);
    }
#endif
}

+ (BOOL)isProfileDowngradeGivenRecordedMajor:(NSInteger)recordedMajor
                                 runningMajor:(NSInteger)runningMajor {
    // recordedMajor <= 0 means absent/unparseable — never a downgrade. Only
    // a STRICTLY newer recorded major is a downgrade; equal or older is not.
    if (recordedMajor <= 0) return NO;
    return recordedMajor > runningMajor;
}

/// Determines the Chromium major version the on-disk profile was last
/// written by. Stamp file first (our own record, written after a prior
/// successful `OnAfterCreated`); falls back to the profile's own
/// `Default/Preferences` → `extensions.last_chrome_version` for profiles
/// that predate the stamp. Returns 0 if neither is present or parseable —
/// 0 is never treated as a downgrade by `isProfileDowngradeGivenRecordedMajor:runningMajor:`.
+ (NSInteger)_recordedChromiumMajorVersionOrZero {
    NSString *stampContents = [NSString stringWithContentsOfFile:[self chromiumVersionStampPath]
                                                          encoding:NSUTF8StringEncoding
                                                             error:nil];
    if (stampContents.length > 0) {
        NSInteger stampedMajor = [stampContents integerValue];
        if (stampedMajor > 0) return stampedMajor;
    }

    // Fallback: profiles written before this guard existed have no stamp.
    NSString *prefsPath = [[self cefProfileDirectoryPath] stringByAppendingPathComponent:@"Default/Preferences"];
    NSData *prefsData = [NSData dataWithContentsOfFile:prefsPath];
    if (!prefsData) return 0;

    id prefsJSON = [NSJSONSerialization JSONObjectWithData:prefsData options:0 error:nil];
    if (![prefsJSON isKindOfClass:[NSDictionary class]]) return 0;

    NSDictionary *extensions = [(NSDictionary *)prefsJSON objectForKey:@"extensions"];
    if (![extensions isKindOfClass:[NSDictionary class]]) return 0;

    NSString *lastChromeVersion = [extensions objectForKey:@"last_chrome_version"];
    if (![lastChromeVersion isKindOfClass:[NSString class]] || lastChromeVersion.length == 0) return 0;

    NSString *majorString = [lastChromeVersion componentsSeparatedByString:@"."].firstObject;
    if (majorString.length == 0) return 0;

    // NSString's -integerValue returns 0 for garbage, which would be
    // indistinguishable from "absent" — reject anything that isn't a clean
    // run of digits so a malformed version string is correctly treated as
    // unparseable rather than as major version 0.
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([majorString rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return 0;

    return [majorString integerValue];
}

/// Runs before `CefInitialize`. See the header doc above
/// `chromiumVersionStampPath` for why: opening a profile last written by a
/// strictly newer Chromium major version than the one currently embedded is
/// the confirmed cause of a deliberate post-init process quit. Moves the
/// ENTIRE profile directory aside when detected (E3/E4 proved the poison is
/// not confined to one file or key) and always logs exactly one line
/// recording the decision, whether or not anything moved.
+ (void)_performDowngradeGuardIfNeeded {
#if GHOSTTIES_CEF_AVAILABLE
    NSInteger recordedMajor = [self _recordedChromiumMajorVersionOrZero];
    NSInteger runningMajor = CHROME_VERSION_MAJOR;

    if (![self isProfileDowngradeGivenRecordedMajor:recordedMajor runningMajor:runningMajor]) {
        os_log(OS_LOG_DEFAULT,
               "[CEFBridge] Downgrade guard: no action (recordedMajor=%ld runningMajor=%ld)",
               (long)recordedMajor, (long)runningMajor);
        return;
    }

    NSError *moveError = nil;
    NSString *movedTo = [self _moveProfileAsideWithPrefix:@"CEF-downgraded" error:&moveError];
    os_log(OS_LOG_DEFAULT,
           "[CEFBridge] Downgrade guard: profile recordedMajor=%ld > runningMajor=%ld — moved aside to "
           "%{public}@ (error=%{public}@)",
           (long)recordedMajor, (long)runningMajor,
           movedTo ?: @"(none)", moveError.localizedDescription ?: @"none");
#endif
}

#pragma mark - Private

+ (void)_messageLoopTick:(NSTimer *)timer {
#if GHOSTTIES_CEF_AVAILABLE
    CefDoMessageLoopWork();
#endif
}

+ (void)_appWillTerminate:(NSNotification *)note {
    if (GhosttiesCEFDiagEnabled()) {
        os_log(OS_LOG_DEFAULT, "[CEFDiag] NSApplicationWillTerminateNotification fired at %{public}@",
               [NSDate date]);
    }
    [self shutdown];
}

@end
