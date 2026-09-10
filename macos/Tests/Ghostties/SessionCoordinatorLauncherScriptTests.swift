// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Guards the `fix/composer-return-to-shell` fix: a spawned session's
/// resolved command must never be the wrapper script's final `exec`'d
/// process. Before this fix, `SessionCoordinator.createSession` wrote
/// `exec \(cmd)` as the script's last line, which replaced the script's
/// process image with the agent — when the agent exited, nothing was left
/// running, so Ghostty printed "Process exited. Press any key to close the
/// terminal." instead of dropping back to a shell.
final class SessionCoordinatorLauncherScriptTests: XCTestCase {

    // MARK: - The fix: command is not the final process

    func testCommandIsNotExecdAsFinalProcess() {
        let script = SessionCoordinator.launcherScript(command: "/usr/local/bin/claude", banner: nil)

        XCTAssertFalse(
            script.contains("exec /usr/local/bin/claude"),
            "the resolved command must run in the foreground, not be exec'd — exec'ing it replaces the " +
            "process image and kills the terminal surface the instant the agent exits"
        )
    }

    func testScriptExecsAFreshLoginShellAsItsFinalLine() {
        let script = SessionCoordinator.launcherScript(command: "/usr/local/bin/claude", banner: nil)
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(
            lines.last(where: { !$0.isEmpty }),
            "exec /bin/zsh -l",
            "the script's final process must be an interactive login shell, so exiting the agent " +
            "lands the user on a normal prompt instead of closing the terminal"
        )
    }

    func testCommandRunsBeforeTheFinalShellExec() {
        let script = SessionCoordinator.launcherScript(command: "/usr/local/bin/claude", banner: nil)

        guard let cmdRange = script.range(of: "/usr/local/bin/claude"),
              let execRange = script.range(of: "exec /bin/zsh -l") else {
            return XCTFail("expected both the command and the trailing shell exec to be present")
        }
        XCTAssertTrue(cmdRange.upperBound <= execRange.lowerBound, "command must run before the final shell exec")
    }

    // MARK: - Consistency: banner and no-banner paths both survive agent exit

    func testNoBannerPathStillExecsAFreshShellAfterCommand() {
        // Guards the second death path called out in the brief: when
        // `template.launchBanner` is nil, the pre-fix code returned the bare
        // command with no wrapper script at all, so Ghostty's own
        // `exec -l <cmd>` wrapping killed the terminal on agent exit too.
        // The fix routes both paths through the same wrapper script.
        let script = SessionCoordinator.launcherScript(command: "/usr/local/bin/claude", banner: nil)

        XCTAssertFalse(script.contains("exec /usr/local/bin/claude"))
        XCTAssertTrue(script.hasSuffix("exec /bin/zsh -l\n"))
    }

    func testBannerPathAlsoExecsAFreshShellAfterCommand() {
        let script = SessionCoordinator.launcherScript(command: "/usr/local/bin/claude", banner: "echo hi")

        XCTAssertFalse(script.contains("exec /usr/local/bin/claude"))
        XCTAssertTrue(script.hasSuffix("exec /bin/zsh -l\n"))
        XCTAssertTrue(script.contains("echo hi"), "banner text must still be printed before the command runs")
    }

    // MARK: - Shell setup preserved

    func testScriptStillSourcesZshrcForPathAndAliases() {
        let script = SessionCoordinator.launcherScript(command: "/usr/local/bin/claude", banner: nil)
        XCTAssertTrue(script.contains(". ~/.zshrc 2>/dev/null"))
    }
}
