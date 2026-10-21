import Foundation
import Testing
@testable import Ghostty

struct CDPPolicyTests {
    @Test(arguments: [
        "Browser.close",
        "Browser.crash",
        "Browser.crashGpuProcess",
        "Browser.setWindowBounds",
        "Browser.executeBrowserCommand",
        // Both smuggle other commands past the policy: sendMessageToTarget
        // carries a nested JSON string, attachToBrowserTarget hands a page
        // client a browser-level session.
        "Target.sendMessageToTarget",
        "Target.attachToBrowserTarget",
    ])
    func deniesBrowserLevelCommandsThatCanEndTheApp(method: String) {
        #expect(CDPPolicy.decide(method: method) == .deny(message: "Ghostties: \(method) is not allowed"))
    }

    @Test func deniesCreateTargetAndPointsAtTheCommand() {
        let verdict = CDPPolicy.decide(method: "Target.createTarget")
        #expect(verdict == .deny(message: "Ghostties: Target.createTarget is not allowed; use `gt browser open`"))
    }

    /// Includes everything Playwright's connectOverCDP sends while attaching.
    @Test(arguments: [
        "Browser.getVersion",
        "Browser.setDownloadBehavior",
        "Browser.grantPermissions",
        "Target.getTargets",
        "Target.setAutoAttach",
        "Target.attachToTarget",
        "Target.closeTarget",
        "Page.navigate",
        "Page.captureScreenshot",
        "Page.close",
        "Runtime.evaluate",
        "Input.dispatchMouseEvent",
        "Network.enable",
    ])
    func allowsEverythingElse(method: String) {
        #expect(CDPPolicy.decide(method: method) == .allow)
    }

    @Test func deniedCommandIsAnsweredWithTheErrorAndNotForwarded() throws {
        let action = CDPPolicy.action(forClientFrame: #"{"id":7,"method":"Browser.close"}"#)
        guard case .reply(let text) = action else {
            Issue.record("expected a reply, got \(action)")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["id"] as? Int == 7)
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32000)
        #expect(error["message"] as? String == "Ghostties: Browser.close is not allowed")
    }

    @Test func replyKeepsTheSessionSoTheClientCanMatchIt() throws {
        let action = CDPPolicy.action(
            forClientFrame: #"{"id":3,"sessionId":"S1","method":"Browser.setWindowBounds","params":{}}"#
        )
        guard case .reply(let text) = action else {
            Issue.record("expected a reply, got \(action)")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["sessionId"] as? String == "S1")
    }

    @Test func createTargetIsAnsweredToo() {
        let action = CDPPolicy.action(forClientFrame: #"{"id":1,"method":"Target.createTarget","params":{"url":"about:blank"}}"#)
        #expect(action == .reply(
            #"{"error":{"code":-32000,"message":"Ghostties: Target.createTarget is not allowed; use `gt browser open`"},"id":1}"#
        ))
    }

    @Test func nestedMessageToATargetIsRefusedNotForwarded() {
        let nested = #"{"id":5,"method":"Target.sendMessageToTarget","params":{"sessionId":"S","message":"{\"id\":1,\"method\":\"Browser.close\"}"}}"#
        guard case .reply(let text) = CDPPolicy.action(forClientFrame: nested) else {
            Issue.record("sendMessageToTarget must be answered with an error, not forwarded")
            return
        }
        #expect(text.contains("Target.sendMessageToTarget is not allowed"))
    }

    @Test func attachToBrowserTargetIsRefusedNotForwarded() {
        let action = CDPPolicy.action(forClientFrame: #"{"id":6,"method":"Target.attachToBrowserTarget"}"#)
        guard case .reply = action else {
            Issue.record("attachToBrowserTarget must be answered with an error, got \(action)")
            return
        }
    }

    @Test func deniedCommandWithoutAnIdIsDroppedNotForwarded() {
        #expect(CDPPolicy.action(forClientFrame: #"{"method":"Browser.close"}"#) == .drop)
    }

    @Test func allowedCommandIsForwarded() {
        #expect(CDPPolicy.action(forClientFrame: #"{"id":1,"method":"Page.navigate","params":{"url":"about:blank"}}"#) == .forward)
    }

    @Test(arguments: [
        "not json at all",
        "",
        "[1,2,3]",
        #"{"id":1}"#,
        #"{"id":1,"method":42}"#,
        #"{"id":1,"method":"Browser.close""#,
    ])
    func malformedFramesAreForwardedUntouched(text: String) {
        #expect(CDPPolicy.action(forClientFrame: text) == .forward)
    }
}
