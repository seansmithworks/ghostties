// C imports here are exposed to Swift.

#import "ObjCExceptionCatcher.h"
#import "VibrantLayer.h"
#import "CEFBridge.h"
#import "CEFBrowserView.h"

#if DEBUG
// Expose the private SPUUserUpdateState initializer for DEBUG-only Sparkle dialog testing.
// The method exists in the compiled Sparkle.framework at runtime; this declaration makes
// it callable from Swift without shipping private headers in release builds.
#import <Sparkle/SPUUserUpdateState.h>
@interface SPUUserUpdateState (GhosttiesDebug)
- (instancetype)initWithStage:(SPUUserUpdateStage)stage userInitiated:(BOOL)userInitiated;
@end
#endif
