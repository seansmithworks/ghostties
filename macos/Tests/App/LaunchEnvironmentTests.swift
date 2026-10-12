import Testing
import Foundation
@testable import Ghostty

struct LaunchEnvironmentTests {
    /// main.swift must set GHOSTTY_RESOURCES_DIR before ghostty_init, because
    /// libghostty snapshots environ there. It runs in the test host too.
    @Test func resourcesDirIsSetBeforeInit() throws {
        let resourcePath = try #require(Bundle.main.resourcePath)
        let value = try #require(getenv("GHOSTTY_RESOURCES_DIR").map { String(cString: $0) })
        #expect(value == resourcePath + "/ghostty")
    }
}
