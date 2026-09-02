#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages CEF lifecycle — lazy initialization, message loop, and shutdown.
/// Thread safety: all methods must be called on the main thread.
@interface CEFBridgeManager : NSObject

/// Whether CEF has been initialized.
@property (class, nonatomic, readonly) BOOL isInitialized;

/// Initialize CEF if not already done. Called lazily on first browser creation.
/// Must be called on the main thread.
+ (void)initializeIfNeeded;

/// Shut down CEF. Must close all browsers first.
/// Called automatically on app termination.
+ (void)shutdown;

#pragma mark - Browser-open sentinel (crash recovery)

// The CEF-profile-poisoning crash (see docs bisection) kills the process in
// ~400-650ms — faster than any in-process watchdog can catch, and nothing
// survives to run recovery code. Recovery is therefore sentinel-based,
// detected on the NEXT launch: a sentinel file is written immediately
// before `CefBrowserHost::CreateBrowser` and cleared only once
// `OnAfterCreated` actually fires. If a later attempt finds an uncleared
// sentinel, the previous attempt almost certainly killed the process.
//
// The sentinel lives OUTSIDE the CEF profile directory (`cefProfileDirectoryPath`)
// so that resetting the profile (moving it aside) never removes it.

/// Path to the CEF profile/cache directory (CefSettings.root_cache_path /
/// cache_path).
+ (NSString *)cefProfileDirectoryPath;

/// Path to the browser-open-attempt sentinel file. A sibling of
/// `cefProfileDirectoryPath`, never inside it.
+ (NSString *)browserOpenAttemptSentinelPath;

/// Writes the sentinel, recording that a browser-open attempt is starting.
+ (void)recordBrowserOpenAttempt;

/// Clears the sentinel. Call only once the browser has actually
/// materialised (`OnAfterCreated`).
+ (void)clearBrowserOpenAttempt;

/// YES if a sentinel from a PRIOR attempt is present and uncleared.
+ (BOOL)hasUnclearedBrowserOpenAttempt;

/// Moves the CEF profile directory aside to a timestamped sibling path
/// (`CEF-broken-<ISO8601>`) — never deletes it — then recreates an empty
/// directory at the original path. Returns the path the old profile was
/// moved to, or nil if there was nothing to move (or on failure; check
/// `error`).
/// `NS_SWIFT_NOTHROW` deliberately opts this out of Swift's automatic
/// NSError**-to-`throws` bridging: that bridging assumes a nil return
/// always means failure, but here nil legitimately means "nothing to move"
/// (no prior profile existed) as well as failure. Tests need to observe
/// both outcomes distinctly via the raw `error` out-parameter.
+ (nullable NSString *)resetProfileDirectoryPreservingDataError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NOTHROW;

#if DEBUG
/// TEST-ONLY. Overrides the base directory all sentinel/profile paths above
/// are derived from (normally `~/Library/Application Support/<bundleId>`).
/// Tests MUST set this to an isolated scratch directory before touching any
/// of the above — `[NSBundle mainBundle] bundleIdentifier]` inside an
/// `xcodebuild test` run resolves to the real Debug app bundle id, so
/// without this override these methods would read/write Sean's real Dev
/// CEF profile on disk. Debug-only; does not exist in Release builds.
@property (class, nonatomic, copy, nullable) NSString *testOverrideAppSupportBundleDirectory;
#endif

@end

NS_ASSUME_NONNULL_END
