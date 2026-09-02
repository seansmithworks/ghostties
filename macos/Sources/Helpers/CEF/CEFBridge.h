#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages CEF lifecycle — lazy initialization, message loop, and shutdown.
/// Thread safety: all methods must be called on the main thread.
@interface CEFBridgeManager : NSObject

/// Whether CEF has been initialized.
@property (class, nonatomic, readonly) BOOL isInitialized;

/// Whether the sentinel from a PRIOR launch was still uncleared at the
/// moment THIS launch's `+initializeIfNeeded` ran — captured once, before
/// this launch writes its own sentinel. The live sentinel file always
/// exists by the time browser creation starts (it is now written before
/// `CefInitialize`, not before `CreateBrowser`), so re-checking
/// `hasUnclearedBrowserOpenAttempt` live at creation time would only ever
/// find THIS launch's own in-flight attempt, not a prior one. Callers that
/// want to know "did the previous launch die" must read this snapshot
/// instead.
@property (class, nonatomic, readonly) BOOL priorLaunchLeftUnclearedAttempt;

/// Call once a detected prior-crash sentinel has been HANDLED — i.e. after
/// `resetProfileDirectoryPreservingDataError:` + `clearBrowserOpenAttempt`
/// have run in response to `priorLaunchLeftUnclearedAttempt` being YES.
/// Without this, the snapshot above stays YES for the rest of the process:
/// a same-launch retry right after a reset would read the ORIGINAL
/// launch-time snapshot again, treat the freshly-reset attempt as ANOTHER
/// crash, and loop within a single launch.
+ (void)acknowledgePriorLaunchAttemptHandled;

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
// before `CefInitialize` and cleared once the process has demonstrably
// survived the death window. If a later attempt finds an uncleared
// sentinel, the previous attempt almost certainly killed the process.
//
// The sentinel lives OUTSIDE the CEF profile directory (`cefProfileDirectoryPath`)
// so that resetting the profile (moving it aside) never removes it.
//
// CORRECTED TWICE (see project_cef-crash-dies-before-createbrowser and the
// round-3 review that removed the CEFBrowserView-owned clear entirely):
// clearing at `OnAfterCreated` is too early — our own measurement shows the
// process dies ~0.33s AFTER `OnAfterCreated` fires (i.e. after a browser
// has already materialised). Clearing from a per-VIEW watchdog (even a 3s
// one) is the wrong SCOPE, not just the wrong timing: a process can host
// several CEFBrowserView tabs at once (BrowserTabManager.browserViews),
// while the sentinel is process-global, so one tab's lifecycle should
// never be able to clear (or fail to clear) it on another tab's behalf.
// The sentinel is therefore cleared EXCLUSIVELY by a process-level timer in
// `+initializeIfNeeded`, started immediately after `CefInitialize` returns
// and firing at the 3s mark — independent of whether any browser view ever
// gets created, how many exist, or when any of them are torn down. An
// uncleared sentinel means exactly one thing: the process died within 3s
// of `CefInitialize` returning.

/// Path to the CEF profile/cache directory (CefSettings.root_cache_path /
/// cache_path).
+ (NSString *)cefProfileDirectoryPath;

/// Path to the browser-open-attempt sentinel file. A sibling of
/// `cefProfileDirectoryPath`, never inside it.
+ (NSString *)browserOpenAttemptSentinelPath;

/// Writes the sentinel, recording that a browser-open attempt is starting.
+ (void)recordBrowserOpenAttempt;

/// Clears the sentinel. Called ONLY from `+initializeIfNeeded`'s
/// process-level 3s-after-`CefInitialize` timer — see the doc block above.
/// Public (not private) so `+resetProfileDirectoryPreservingDataError:`
/// callers and tests can still exercise it directly; production code
/// outside `CEFBridge.mm` should not call this.
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

#pragma mark - Downgrade guard (Chromium major-version stamp)

// PR #60 pinned vendor/cef at a fixed Chromium major version. A profile
// last written by a NEWER Chromium than the one currently embedded is an
// unsupported downgrade that Chromium resolves by quietly quitting
// ~0.4-0.65s after `CefInitialize` returns (see the CEF profile-poisoning
// bisection — root cause is a Chromium 150→144 profile downgrade, not a
// crash in the ordinary sense). This guard runs before `CefInitialize` on
// every launch and moves such a profile aside before it is ever opened.
//
// E3/E4 (see docs/plans lab notes) proved the poison is not confined to one
// preference key or file: the remediation below moves the ENTIRE `CEF/`
// directory aside, never a targeted rewrite.

/// Path to the Chromium-major-version stamp file. A SIBLING of
/// `cefProfileDirectoryPath` — same reasoning as the sentinel above, a
/// profile move-aside must never also remove the record of what wrote it.
+ (NSString *)chromiumVersionStampPath;

/// Records the currently-running embedded Chromium's major version to the
/// stamp file. Call only once a browser has actually materialised
/// (`OnAfterCreated`) — a stamp written any earlier would claim a version
/// ran successfully when it may not have.
+ (void)recordChromiumVersionStamp;

/// The pure comparison the downgrade guard's decision reduces to: is a
/// profile last written by `recordedMajor` an unsupported downgrade when
/// opened by an embedded Chromium whose major version is `runningMajor`?
/// `recordedMajor <= 0` means absent/unparseable and is never a downgrade.
/// Exposed as its own symbol so it can be tested directly — see
/// CEFBrowserSentinelTests.
+ (BOOL)isProfileDowngradeGivenRecordedMajor:(NSInteger)recordedMajor
                                 runningMajor:(NSInteger)runningMajor;

#if DEBUG
/// TEST-ONLY. Overrides the base directory all sentinel/profile paths above
/// are derived from (normally `~/Library/Application Support/<bundleId>`).
/// Tests MUST set this to an isolated scratch directory before touching any
/// of the above — `[NSBundle mainBundle] bundleIdentifier]` inside an
/// `xcodebuild test` run resolves to the real Debug app bundle id, so
/// without this override these methods would read/write Sean's real Dev
/// CEF profile on disk. Debug-only; does not exist in Release builds.
@property (class, nonatomic, copy, nullable) NSString *testOverrideAppSupportBundleDirectory;

/// TEST-ONLY. Exposes the downgrade guard's version-parsing logic directly
/// (stamp file first, falling back to `Default/Preferences` ->
/// `extensions.last_chrome_version`, both validated and bounded — see
/// `chromiumVersionStampPath` / `isProfileDowngradeGivenRecordedMajor:runningMajor:`)
/// so tests can exercise every parse path without driving a full CEF init.
/// Reads relative to whatever `testOverrideAppSupportBundleDirectory` points
/// at. Debug-only; does not exist in Release builds.
+ (NSInteger)recordedChromiumMajorVersionOrZeroForTesting;
#endif

@end

NS_ASSUME_NONNULL_END
