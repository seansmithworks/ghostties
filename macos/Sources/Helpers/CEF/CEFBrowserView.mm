#import "CEFBrowserView.h"
#import "CEFBridge.h"
#import <AppKit/AppKit.h>
#if DEBUG
#import <os/log.h>
#endif

// CEF headers are only available after running scripts/download-cef.sh.
// When absent, the view compiles in stub mode — all methods are no-ops.
#define GHOSTTIES_CEF_AVAILABLE __has_include("include/cef_browser.h")

#if GHOSTTIES_CEF_AVAILABLE
#import "include/cef_browser.h"
#import "include/cef_client.h"
#import "include/cef_life_span_handler.h"
#import "include/cef_display_handler.h"
#import "include/cef_load_handler.h"
#import "include/wrapper/cef_helpers.h"
#endif

// ---------------------------------------------------------------------------
// URL scheme allowlist — only http, https, and about are permitted.
// ---------------------------------------------------------------------------

static BOOL GhosttiesIsAllowedScheme(NSString *urlString) {
    if (!urlString || urlString.length == 0) return NO;
    NSString *lower = [urlString lowercaseString];
    return [lower hasPrefix:@"https://"]
        || [lower hasPrefix:@"http://"]
        || [lower hasPrefix:@"about:"];
}

#if GHOSTTIES_CEF_AVAILABLE
static bool GhosttiesIsAllowedSchemeCef(const CefString &url) {
    if (url.empty()) return false;
    std::string s = url.ToString();
    // Convert only the scheme portion to lowercase for comparison.
    std::string lower;
    lower.reserve(8);
    for (size_t i = 0; i < s.size() && i < 8; ++i) {
        lower += static_cast<char>(tolower(static_cast<unsigned char>(s[i])));
    }
    return lower.compare(0, 8, "https://") == 0
        || lower.compare(0, 7, "http://") == 0
        || lower.compare(0, 6, "about:") == 0;
}
#endif

// Forward-declare private methods so C++ handlers can call them.
@interface CEFBrowserView ()
- (void)_didChangeURL:(NSString *)url;
- (void)_didChangeTitle:(NSString *)title;
- (void)_didChangeLoadingState:(BOOL)loading canGoBack:(BOOL)back canGoForward:(BOOL)forward;
- (void)_notifyCreationFailed;
#if GHOSTTIES_CEF_AVAILABLE
- (void)_createBrowserNow;
- (void)_startCreationWatchdog;
- (void)_browserDidCreate:(CefRefPtr<CefBrowser>)browser;
- (void)_browserDidClose;
#endif
@end

#if GHOSTTIES_CEF_AVAILABLE

#pragma mark - GhosttiesDisplayHandler

class GhosttiesDisplayHandler : public CefDisplayHandler {
public:
    explicit GhosttiesDisplayHandler(CEFBrowserView *view) : view_(view) {}

    void OnAddressChange(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefFrame> frame,
                         const CefString &url) override {
        if (!frame->IsMain()) return;
        CEFBrowserView *v = view_;
        if (!v) return;
        NSString *nsURL = [NSString stringWithUTF8String:url.ToString().c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
            [v _didChangeURL:nsURL];
        });
    }

    void OnTitleChange(CefRefPtr<CefBrowser> browser,
                       const CefString &title) override {
        CEFBrowserView *v = view_;
        if (!v) return;
        NSString *nsTitle = [NSString stringWithUTF8String:title.ToString().c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
            [v _didChangeTitle:nsTitle];
        });
    }

private:
    __weak CEFBrowserView *view_;
    IMPLEMENT_REFCOUNTING(GhosttiesDisplayHandler);
};

#pragma mark - GhosttiesLoadHandler

class GhosttiesLoadHandler : public CefLoadHandler {
public:
    explicit GhosttiesLoadHandler(CEFBrowserView *view) : view_(view) {}

    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) override {
        CEFBrowserView *v = view_;
        if (!v) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [v _didChangeLoadingState:isLoading
                            canGoBack:canGoBack
                         canGoForward:canGoForward];
        });
    }

private:
    __weak CEFBrowserView *view_;
    IMPLEMENT_REFCOUNTING(GhosttiesLoadHandler);
};

#pragma mark - GhosttiesLifeSpanHandler

class GhosttiesLifeSpanHandler : public CefLifeSpanHandler {
public:
    explicit GhosttiesLifeSpanHandler(CEFBrowserView *view) : view_(view) {}

    // Intercept all popups — user-gesture popups navigate the current browser
    // instead of opening a new window; non-user-gesture popups are blocked
    // entirely to prevent uncontrolled popup windows.
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       int popup_id,
                       const CefString& target_url,
                       const CefString& target_frame_name,
                       CefLifeSpanHandler::WindowOpenDisposition target_disposition,
                       bool user_gesture,
                       const CefPopupFeatures& popupFeatures,
                       CefWindowInfo& windowInfo,
                       CefRefPtr<CefClient>& client,
                       CefBrowserSettings& settings,
                       CefRefPtr<CefDictionaryValue>& extra_info,
                       bool* no_javascript_access) override {
        // Redirect explicit user clicks (target=_blank links) to current browser.
        if (user_gesture && !target_url.empty()) {
            // Block disallowed schemes (file://, javascript://, data://, etc.).
            if (!GhosttiesIsAllowedSchemeCef(target_url)) {
                NSLog(@"[CEFBrowserView] Blocked popup with disallowed scheme: %s",
                      target_url.ToString().c_str());
                return true;  // Cancel the popup.
            }
            browser->GetMainFrame()->LoadURL(target_url);
            return true;
        }
        return true;  // Block all non-user-gesture popups.
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
#if DEBUG
        NSLog(@"[CEFDiag] OnAfterCreated fired — browser materialised.");
#endif
        CEFBrowserView *v = view_;
        if (v) {
            [v _browserDidCreate:browser];
        }
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        CEFBrowserView *v = view_;
        if (v) {
            [v _browserDidClose];
        }
    }

private:
    __weak CEFBrowserView *view_;
    IMPLEMENT_REFCOUNTING(GhosttiesLifeSpanHandler);
};

#pragma mark - GhosttiesCefClient

class GhosttiesCefClient : public CefClient {
public:
    GhosttiesCefClient(CEFBrowserView *view)
        : life_span_handler_(new GhosttiesLifeSpanHandler(view))
        , display_handler_(new GhosttiesDisplayHandler(view))
        , load_handler_(new GhosttiesLoadHandler(view)) {}

    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override {
        return life_span_handler_;
    }

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override {
        return display_handler_;
    }

    CefRefPtr<CefLoadHandler> GetLoadHandler() override {
        return load_handler_;
    }

private:
    CefRefPtr<GhosttiesLifeSpanHandler> life_span_handler_;
    CefRefPtr<GhosttiesDisplayHandler> display_handler_;
    CefRefPtr<GhosttiesLoadHandler> load_handler_;
    IMPLEMENT_REFCOUNTING(GhosttiesCefClient);
};

#endif // GHOSTTIES_CEF_AVAILABLE

#pragma mark - CEFBrowserView private interface

@interface CEFBrowserView () {
#if GHOSTTIES_CEF_AVAILABLE
    CefRefPtr<CefBrowser> _browser;
    CefRefPtr<GhosttiesCefClient> _client;
#endif
}

#if DEBUG
/// Set from OnAfterCreated (via -_browserDidCreate:), read by the
/// CreateBrowser watchdog to report whether the browser ever materialised.
@property (nonatomic) BOOL diagAfterCreatedFired;
#endif

@property (nonatomic, readwrite) BOOL isLoading;
@property (nonatomic, readwrite) BOOL canGoBack;
@property (nonatomic, readwrite) BOOL canGoForward;
@property (nonatomic, readwrite, nullable) NSString *currentURL;
@property (nonatomic, readwrite, nullable) NSString *currentTitle;
@property (nonatomic, readwrite) BOOL browserCreated;
@property (nonatomic, readwrite) NSInteger creationAttemptCount;
@property (nonatomic, readwrite) BOOL creationFailed;
@property (nonatomic, readwrite) BOOL creationFailedDueToPreviousCrash;
@property (nonatomic, readwrite) BOOL isDevToolsOpen;
/// Pending URL captured at init time; consumed the moment creation is
/// actually attempted (deferred until the view is in a window).
@property (nonatomic, copy, nullable) NSString *pendingURL;
/// One-shot timer started right after `CreateBrowser` is called. If
/// `OnAfterCreated` hasn't fired by the time it elapses, creation is
/// treated as failed. Ships in Release — this is a behavioral safety net,
/// not a diagnostic.
@property (nonatomic, strong, nullable) NSTimer *creationWatchdogTimer;

@end

#pragma mark - CEFBrowserView implementation

@implementation CEFBrowserView

- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url {
    // Ensure non-zero frame — CEF's compositor aborts on zero-sized views.
    NSRect initialFrame = frame;
    if (initialFrame.size.width < 1) initialFrame.size.width = 800;
    if (initialFrame.size.height < 1) initialFrame.size.height = 600;

    self = [super initWithFrame:initialFrame];
    if (!self) return nil;

    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;
    self.browserCreated = NO;

    self.pendingURL = url ?: @"about:blank";

#if GHOSTTIES_CEF_AVAILABLE
    [CEFBridgeManager initializeIfNeeded];
    if (![CEFBridgeManager isInitialized]) {
        // CEF failed to init — stub view. Notify the failure asynchronously
        // so the delegate (assigned by the caller right after this
        // initializer returns) is in place by the time it fires.
        self.creationFailed = YES;
        __weak CEFBrowserView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _notifyCreationFailed];
        });
        return self;
    }

    _client = new GhosttiesCefClient(self);

    // Creation is deferred to -viewDidMoveToWindow — see that method.
    // `SetAsChild` requires a view that is already in a window; calling it
    // here, before the view has ever been added to a superview, guarantees
    // CreateBrowser fails.
#else
    NSLog(@"[CEFBrowserView] CEF headers not available — running in stub mode.");
    self.creationFailed = YES;
    __weak CEFBrowserView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf _notifyCreationFailed];
    });
#endif

    return self;
}

- (void)dealloc {
    [_creationWatchdogTimer invalidate];
    _creationWatchdogTimer = nil;
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) {
        _browser->GetHost()->CloseBrowser(true);
        _browser = nullptr;
    }
    _client = nullptr;
#endif
}

#pragma mark - Navigation

- (void)loadURL:(NSString *)url {
#if GHOSTTIES_CEF_AVAILABLE
    if (!GhosttiesIsAllowedScheme(url)) {
        NSLog(@"[CEFBrowserView] Blocked loadURL with disallowed scheme: %@", url);
        return;
    }
    if (_browser && _browser->GetMainFrame()) {
        _browser->GetMainFrame()->LoadURL(CefString([url UTF8String]));
    }
#else
    NSLog(@"[CEFBrowserView] loadURL: stub — CEF not available");
#endif
}

- (void)goBack {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) _browser->GoBack();
#else
    NSLog(@"[CEFBrowserView] goBack: stub — CEF not available");
#endif
}

- (void)goForward {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) _browser->GoForward();
#else
    NSLog(@"[CEFBrowserView] goForward: stub — CEF not available");
#endif
}

- (void)reload {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) _browser->Reload();
#else
    NSLog(@"[CEFBrowserView] reload: stub — CEF not available");
#endif
}

- (void)stopLoading {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) _browser->StopLoad();
#else
    NSLog(@"[CEFBrowserView] stopLoading: stub — CEF not available");
#endif
}

#pragma mark - DevTools

- (void)showInlineDevTools:(NSView *)parentView {
#if GHOSTTIES_CEF_AVAILABLE
    if (!_browser) return;

    NSRect parentBounds = parentView.bounds;
    if (parentBounds.size.width < 1) parentBounds.size.width = 400;
    if (parentBounds.size.height < 1) parentBounds.size.height = 200;

    CefWindowInfo devToolsWindowInfo;
    CefRect cefRect(0, 0,
                    (int)parentBounds.size.width,
                    (int)parentBounds.size.height);
    devToolsWindowInfo.SetAsChild((__bridge CefWindowHandle)parentView, cefRect);

    CefBrowserSettings devToolsSettings;
    CefPoint inspectPoint;

    _browser->GetHost()->ShowDevTools(devToolsWindowInfo, _client,
                                      devToolsSettings, inspectPoint);
    self.isDevToolsOpen = YES;
#else
    NSLog(@"[CEFBrowserView] showInlineDevTools: stub — CEF not available");
#endif
}

- (void)closeDevTools {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) {
        _browser->GetHost()->CloseDevTools();
        self.isDevToolsOpen = NO;
    }
#else
    NSLog(@"[CEFBrowserView] closeDevTools: stub — CEF not available");
#endif
}

#pragma mark - Lifecycle

- (void)closeBrowser {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) {
        _browser->GetHost()->CloseBrowser(true);
        // _browser is nilled in OnBeforeClose callback
    }
#else
    NSLog(@"[CEFBrowserView] closeBrowser: stub — CEF not available");
#endif
}

#pragma mark - Layout

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
#if GHOSTTIES_CEF_AVAILABLE
    [self _syncCefChildBounds];
#endif
}

- (void)layout {
    [super layout];
}

/// Resize CEF's internal child view to match our bounds and notify the compositor.
- (void)_syncCefChildBounds {
#if GHOSTTIES_CEF_AVAILABLE
    // CEF inserts its own NSView as a child. It doesn't auto-resize with us,
    // so we must explicitly set its frame to fill our bounds.
    BOOL boundsChanged = NO;
    for (NSView *child in self.subviews) {
        if (child != self && ![child isKindOfClass:[NSTextField class]]) {
            if (!NSEqualRects(child.frame, self.bounds)) {
                child.frame = self.bounds;
                boundsChanged = YES;
            }
        }
    }
    if (boundsChanged && _browser) {
        _browser->GetHost()->WasResized();
    }
#endif
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
#if GHOSTTIES_CEF_AVAILABLE
    // Final notification after the user finishes dragging the window edge.
    // Guarantees the compositor settles on the correct size even if
    // intermediate WasResized() calls were coalesced during the drag.
    if (_browser) {
        _browser->GetHost()->WasResized();
    }
#endif
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser && self.window) {
        _browser->GetHost()->WasResized();
    }
    // Create the browser the first time this view lands in a real window.
    // `browserCreated` guards against a second attempt if the view is later
    // removed from its window and re-added (e.g. re-parented into a
    // different panel) — it is only cleared by an explicit retry.
    if (!self.browserCreated && self.window && _client) {
        [self _createBrowserNow];
    }
#endif
}

#if GHOSTTIES_CEF_AVAILABLE
/// Actually call `CefBrowserHost::CreateBrowser`. Only ever called from a
/// path where `self.window != nil` (either -viewDidMoveToWindow, or
/// -retryCreateBrowser when the view is already attached).
- (void)_createBrowserNow {
    if (self.browserCreated) return;

    // Sentinel-based crash recovery: the CEF-profile-poisoning crash kills
    // the process in ~400-650ms — far faster than the 3s creation watchdog
    // below can ever catch, and nothing in-process survives to run recovery
    // code. So this is checked here, on the NEXT launch, instead: if a
    // prior attempt wrote the sentinel and never cleared it (never survived
    // 3s past CreateBrowser — see -_startCreationWatchdog), that attempt
    // almost certainly killed the process. Do NOT attempt creation again
    // blind — surface the failure state and let the user choose to reset
    // the profile.
    //
    // This reads the SNAPSHOT captured by +[CEFBridgeManager
    // initializeIfNeeded], not the live sentinel file: the sentinel is now
    // written before CefInitialize, so by the time this method runs the
    // file always exists as THIS launch's own in-flight attempt.
    if ([CEFBridgeManager priorLaunchLeftUnclearedAttempt]) {
        self.browserCreated = YES;
        self.creationFailedDueToPreviousCrash = YES;
#if DEBUG
        os_log(OS_LOG_DEFAULT, "[CEFDiag] Prior launch left the browser-open-attempt sentinel uncleared — "
               "skipping CreateBrowser, surfacing failure state instead.");
#endif
        [self _notifyCreationFailed];
        return;
    }

    self.browserCreated = YES;
    self.creationAttemptCount += 1;

    CefWindowInfo windowInfo;
    CefRect cefRect(0, 0, (int)self.frame.size.width, (int)self.frame.size.height);
    windowInfo.SetAsChild((__bridge CefWindowHandle)self, cefRect);

    CefBrowserSettings settings;
    NSString *urlStr = self.pendingURL ?: @"about:blank";
    CefString cefURL([urlStr UTF8String]);

#if DEBUG
    // Diagnostic 4: the view's window state at the exact moment CreateBrowser
    // is called. Now guaranteed non-nil by the -viewDidMoveToWindow guard.
    // NSLog does not honor `{public}` (that annotation only means something
    // to os_log()/os_trace() — clang warns on the NSLog call site, and the
    // unified log corrupts the argument decode instead of un-redacting it).
    // os_log() is the mechanism that actually makes these values visible.
    os_log(OS_LOG_DEFAULT,
           "[CEFDiag] Pre-CreateBrowser window state: window=%{public}@ superview=%{public}@ frame=%{public}@",
           self.window, self.superview, NSStringFromRect(self.frame));
    os_log(OS_LOG_DEFAULT, "[CEFDiag] Calling CefBrowserHost::CreateBrowser (async) for url=%{public}@", urlStr);
#endif
    CefBrowserHost::CreateBrowser(windowInfo, _client, cefURL, settings,
                                  nullptr, nullptr);

#if DEBUG
    // Diagnostic 3: log-only watchdog, independent of the production one
    // below. Reports whether OnAfterCreated has fired yet, plus the view's
    // window hierarchy state at each tick.
    __weak CEFBrowserView *diagWeakSelf = self;
    for (NSNumber *delaySeconds in @[@2.0, @5.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                      (int64_t)(delaySeconds.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CEFBrowserView *strongSelf = diagWeakSelf;
            if (!strongSelf) {
                os_log(OS_LOG_DEFAULT, "[CEFDiag] CreateBrowser watchdog (%{public}@s): view deallocated",
                       delaySeconds);
                return;
            }
            os_log(OS_LOG_DEFAULT,
                   "[CEFDiag] CreateBrowser watchdog (%{public}@s): OnAfterCreated fired=%{public}@ "
                   "window=%{public}@ superview=%{public}@ frame=%{public}@",
                   delaySeconds, strongSelf.diagAfterCreatedFired ? @"YES" : @"NO",
                   strongSelf.window, strongSelf.superview,
                   NSStringFromRect(strongSelf.frame));
        });
    }
#endif

    [self _startCreationWatchdog];
}

/// Ships in Release — this is the real safety net, not a diagnostic. If
/// `OnAfterCreated` hasn't fired within 3s of calling `CreateBrowser`,
/// treat creation as failed so nothing downstream waits on a browser that
/// will never materialise.
///
/// ALSO owns clearing the browser-open-attempt sentinel (see
/// CEFBridgeManager) once the browser HAS materialised. `OnAfterCreated`
/// firing does not prove the process has survived the CEF profile-downgrade
/// crash — it kills the process ~0.3-0.65s *after* `OnAfterCreated`, inside
/// this same 3s window — so the clear happens here, at 3s, not there.
- (void)_startCreationWatchdog {
    [self.creationWatchdogTimer invalidate];
    self.creationFailed = NO;
    __weak CEFBrowserView *weakSelf = self;
    self.creationWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                                  repeats:NO
                                                                    block:^(NSTimer *timer) {
        CEFBrowserView *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf->_browser) {
            // Already materialised, and the process has now survived a
            // further 3s past CreateBrowser — the earliest point we can be
            // sure this launch is not the profile-downgrade crash. Clear
            // the sentinel here, not at OnAfterCreated.
            [CEFBridgeManager clearBrowserOpenAttempt];
            strongSelf.creationWatchdogTimer = nil;
            return;
        }
#if DEBUG
        NSLog(@"[CEFDiag] Creation watchdog: OnAfterCreated did not fire within "
              @"3.0s — treating creation as failed.");
#endif
        [strongSelf _notifyCreationFailed];
    }];
}
#endif // GHOSTTIES_CEF_AVAILABLE

- (void)retryCreateBrowser {
#if GHOSTTIES_CEF_AVAILABLE
    if (_browser) return;  // already succeeded
    [self.creationWatchdogTimer invalidate];
    self.creationWatchdogTimer = nil;
    self.browserCreated = NO;
    self.creationFailed = NO;
    self.creationFailedDueToPreviousCrash = NO;
    if (self.window && _client) {
        [self _createBrowserNow];
    }
    // Else: -viewDidMoveToWindow will pick it up once the view lands in a
    // window again.
#else
    // No CEF headers at all — nothing to retry. Re-notify so the caller's
    // failure UI stays consistent.
    __weak CEFBrowserView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf _notifyCreationFailed];
    });
#endif
}

- (void)resetProfileDataAndRetry:(void (^)(NSString * _Nullable movedToPath, NSError * _Nullable error))completion {
#if GHOSTTIES_CEF_AVAILABLE
    NSError *error = nil;
    NSString *movedToPath = [CEFBridgeManager resetProfileDirectoryPreservingDataError:&error];
    [CEFBridgeManager clearBrowserOpenAttempt];

    [self.creationWatchdogTimer invalidate];
    self.creationWatchdogTimer = nil;
    self.browserCreated = NO;
    self.creationFailed = NO;
    self.creationFailedDueToPreviousCrash = NO;

    if (completion) completion(movedToPath, error);

    if (self.window && _client) {
        [self _createBrowserNow];
    }
    // Else: -viewDidMoveToWindow will pick it up once the view lands in a
    // window again.
#else
    if (completion) completion(nil, nil);
    __weak CEFBrowserView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf _notifyCreationFailed];
    });
#endif
}

#pragma mark - Internal callbacks (called from C++ handlers)

- (void)_didChangeURL:(NSString *)url {
    self.currentURL = url;
    if ([self.delegate respondsToSelector:@selector(browserView:didChangeURL:)]) {
        [self.delegate browserView:self didChangeURL:url];
    }
}

- (void)_didChangeTitle:(NSString *)title {
    self.currentTitle = title;
    if ([self.delegate respondsToSelector:@selector(browserView:didChangeTitle:)]) {
        [self.delegate browserView:self didChangeTitle:title];
    }
}

- (void)_didChangeLoadingState:(BOOL)loading
                      canGoBack:(BOOL)back
                   canGoForward:(BOOL)forward {
    self.isLoading = loading;
    self.canGoBack = back;
    self.canGoForward = forward;
    if ([self.delegate respondsToSelector:
             @selector(browserView:didChangeLoadingState:canGoBack:canGoForward:)]) {
        [self.delegate browserView:self didChangeLoadingState:loading
                         canGoBack:back canGoForward:forward];
    }
}

- (void)_notifyCreationFailed {
    self.creationFailed = YES;
    if ([self.delegate respondsToSelector:@selector(browserViewDidFailToCreate:)]) {
        [self.delegate browserViewDidFailToCreate:self];
    }
}

#if GHOSTTIES_CEF_AVAILABLE
- (void)_browserDidCreate:(CefRefPtr<CefBrowser>)browser {
#if DEBUG
    self.diagAfterCreatedFired = YES;
#endif
    // Deliberately do NOT invalidate the creation watchdog here, and do NOT
    // clear the browser-open-attempt sentinel here — see the doc comment on
    // -_startCreationWatchdog. The watchdog keeps running and clears the
    // sentinel once the browser has survived a further 3s.
    self.creationFailed = NO;
    self.creationFailedDueToPreviousCrash = NO;
    _browser = browser;
    // Record which Chromium major version this profile was just opened
    // successfully by, so the downgrade guard on the NEXT launch has a
    // record even for profiles that predate it.
    [CEFBridgeManager recordChromiumVersionStamp];
    // Sync CEF's internal child view and compositor to our current bounds.
    [self _syncCefChildBounds];
    if ([self.delegate respondsToSelector:@selector(browserViewDidCreate:)]) {
        [self.delegate browserViewDidCreate:self];
    }
}

- (void)_browserDidClose {
    _browser = nullptr;
}
#endif

@end
