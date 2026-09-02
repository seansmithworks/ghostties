#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class CEFBrowserView;

@protocol CEFBrowserViewDelegate <NSObject>
@optional
- (void)browserView:(CEFBrowserView *)view didChangeURL:(NSString *)url;
- (void)browserView:(CEFBrowserView *)view didChangeTitle:(NSString *)title;
- (void)browserView:(CEFBrowserView *)view didChangeLoadingState:(BOOL)isLoading
         canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
/// Fired when browser creation could not be completed — either CEF itself
/// never initialized, or `CefBrowserHost::CreateBrowser` was called but
/// `OnAfterCreated` never fired within the creation watchdog window.
- (void)browserViewDidFailToCreate:(CEFBrowserView *)view;
/// Fired when the browser successfully materialises (`OnAfterCreated`).
/// Lets UI that showed an inline failure state (including after a retry)
/// know it can dismiss it.
- (void)browserViewDidCreate:(CEFBrowserView *)view;
@end

/// Hosts a single CEF browser instance as an NSView.
/// Each instance is a separate Chromium renderer process.
@interface CEFBrowserView : NSView

@property (nonatomic, weak, nullable) id<CEFBrowserViewDelegate> delegate;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly, nullable) NSString *currentURL;
@property (nonatomic, readonly, nullable) NSString *currentTitle;
@property (nonatomic, readonly) BOOL isDevToolsOpen;
/// YES once browser creation has been attempted (successfully or not) for
/// the current attempt. Attempting again after a failure requires
/// `-retryCreateBrowser`, which resets this before trying again.
@property (nonatomic, readonly) BOOL browserCreated;
/// Number of times `CefBrowserHost::CreateBrowser` has actually been
/// invoked. Used to prove the window-attach guard never double-creates.
@property (nonatomic, readonly) NSInteger creationAttemptCount;
/// YES if the most recent creation attempt failed — either CEF is
/// unavailable, or the creation watchdog timed out.
@property (nonatomic, readonly) BOOL creationFailed;
/// YES if the most recent creation failure was detected via the
/// browser-open-attempt sentinel — i.e. a PRIOR launch's attempt left an
/// uncleared sentinel, meaning it almost certainly killed the process
/// before `OnAfterCreated` could fire. `-retryCreateBrowser` is unsafe to
/// call blind in this state; offer `-resetProfileDataAndRetry:` instead.
@property (nonatomic, readonly) BOOL creationFailedDueToPreviousCrash;

- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url;
- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
/// Open DevTools inline inside the given parent view.
- (void)showInlineDevTools:(NSView *)parentView;
/// Close DevTools (works for both popup and inline).
- (void)closeDevTools;
- (void)closeBrowser;
/// Attempt browser creation again after a failure. No-op if a browser
/// already exists or is already pending. Unsafe to rely on alone when
/// `creationFailedDueToPreviousCrash` is YES — it will simply re-detect the
/// same uncleared sentinel and fail again without risking another crash,
/// but it will not recover. Use `-resetProfileDataAndRetry:` in that case.
- (void)retryCreateBrowser;

/// Moves the CEF profile directory aside (never deletes — cookies/logins
/// are preserved at the new path), clears the crash sentinel, then retries
/// creation once. `completion` is called on the main thread with the path
/// the old profile was moved to (nil if there was nothing to move) and any
/// filesystem error, before the retry attempt is made.
- (void)resetProfileDataAndRetry:(void (^_Nullable)(NSString * _Nullable movedToPath, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
