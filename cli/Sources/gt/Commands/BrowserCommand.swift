import ArgumentParser
import Foundation
import GhosttiesCore

struct BrowserCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "browser",
        abstract: "Drive the browser inside Ghostties Dev.",
        subcommands: [OpenSubcommand.self]
    )

    struct OpenSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "open",
            abstract: "Open a URL in a browser beside this terminal and print how to attach a CDP client.",
            discussion: """
            Prints {"endpoint","targetId","wsUrl"}. Point Playwright's connectOverCDP at
            "endpoint", or a raw CDP client at "wsUrl". The user's selection and focus
            are not touched. Needs a Ghostties Dev terminal.
            """
        )

        @Argument(help: "An http, https or about: URL.")
        var url: String

        func run() throws {
            print(try BrowserControl.open(url: url))
        }
    }
}
