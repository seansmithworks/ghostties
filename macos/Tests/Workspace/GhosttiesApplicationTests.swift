import AppKit
import Testing
@testable import Ghostty

/// CEF calls `-[NSApp isHandlingSendEvent]` from inside Chromium (e.g. while
/// closing a browser). A plain `NSApplication` throws "unrecognized selector"
/// there and the app dies. These tests pin that the hosted app's real `NSApp`
/// is the CEF-conforming principal class.
@MainActor
struct GhosttiesApplicationTests {
    @Test func principalClassIsGhosttiesApplication() {
        let principal = Bundle.main.object(forInfoDictionaryKey: "NSPrincipalClass") as? String
        #expect(principal == "GhosttiesApplication")
        #expect(NSApp is GhosttiesApplication)
    }

    @Test func nsAppRespondsToCefSendEventSelectors() {
        #expect(NSApp.responds(to: NSSelectorFromString("isHandlingSendEvent")))
        #expect(NSApp.responds(to: NSSelectorFromString("setHandlingSendEvent:")))
    }

    @Test func nsAppConformsToCefAppProtocolWhenCefIsLinked() {
        // The protocol only exists in builds compiled against the CEF headers.
        guard let cefAppProtocol = NSProtocolFromString("CefAppProtocol") else { return }
        #expect(NSApp.conforms(to: cefAppProtocol))
    }

    @Test func handlingSendEventFlagRoundTrips() throws {
        let app = try #require(NSApp as? GhosttiesApplication)
        let original = app.isHandlingSendEvent()
        defer { app.setHandlingSendEvent(original) }

        app.setHandlingSendEvent(true)
        #expect(app.isHandlingSendEvent() == true)
        app.setHandlingSendEvent(false)
        #expect(app.isHandlingSendEvent() == false)
    }
}
