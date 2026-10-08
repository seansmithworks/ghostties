#import "GhosttiesApplication.h"

#if __has_include("include/cef_application_mac.h")
#define GHOSTTIES_CEF_APP_PROTOCOL 1
#import "include/cef_application_mac.h"
#else
#define GHOSTTIES_CEF_APP_PROTOCOL 0
#endif

#if GHOSTTIES_CEF_APP_PROTOCOL
@interface GhosttiesApplication () <CefAppProtocol>
@end
#endif

@implementation GhosttiesApplication {
    BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
    return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
#if GHOSTTIES_CEF_APP_PROTOCOL
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
#else
    // No CEF in this build: keep the same contract by hand.
    BOOL wasHandling = _handlingSendEvent;
    _handlingSendEvent = YES;
    @try {
        [super sendEvent:event];
    } @finally {
        _handlingSendEvent = wasHandling;
    }
#endif
}

@end
