#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The app's principal `NSApplication` class (Info.plist `NSPrincipalClass`).
///
/// CEF requires every client app's NSApplication to implement
/// `CefAppProtocol` (`isHandlingSendEvent` / `setHandlingSendEvent:`) and to
/// wrap `sendEvent:` in `CefScopedSendingEvent`. Chromium calls
/// `-[NSApp isHandlingSendEvent]` from its own event handling — for example
/// while tearing down a browser — and a plain `NSApplication` throws
/// "unrecognized selector" there, killing the app.
@interface GhosttiesApplication : NSApplication

/// YES while `-sendEvent:` is on the stack. Read by Chromium.
- (BOOL)isHandlingSendEvent;

/// Set by `CefScopedSendingEvent` around `-sendEvent:`.
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;

@end

NS_ASSUME_NONNULL_END
