import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Step 7 (Composer UI 11 plan §5/§7) — model B spike tests.
///
/// **What these tests do NOT prove**, stated per the acceptance criteria:
/// the `doCommandBySelector` tests below call
/// `Coordinator.textView(_:doCommandBy:)` DIRECTLY with a selector — they
/// bypass `NSWindow.sendEvent:`/`performKeyEquivalent:`/`interpretKeyEvents:`
/// entirely (A-F12). They prove the switch statement's own logic (which
/// event fires, what the guard ladder does, that `cancelOperation:` and the
/// arrows return `true`) — nothing about whether a real keystroke, routed
/// through the real window, ever reaches this method. Event ROUTING is
/// exactly the thing A-F12/A-F13 say cannot be verified here.
@MainActor
struct ComposerGhostTextFieldTests {
    // MARK: - Flag default (acceptance criterion 3)

    /// The flag's `@AppStorage` default, isolated against whatever value
    /// might already be sitting in `UserDefaults.standard` (this repo's
    /// other composer flags — `sidebarTab`, `hasSeenOnboarding` — use the
    /// same implicit `.standard` store, so a prior test run or a real
    /// `defaults write` from Sean's own hands-on pass could otherwise leak
    /// into this assertion). Restores whatever was there afterward.
    @Test func flagDefaultsToOffAndDefaultPathBuildsComposerQueryField() {
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let project = Project(name: "Demo", rootPath: "/tmp/composer-ui-11-modelb-flag-\(UUID().uuidString)")
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        // `usesModelBFieldForTesting` is the EXACT predicate `queryRow`
        // branches its `if` on (see that property's doc comment for why a
        // view-tree/type-name reflection test would be vacuous here). With
        // the key cleared, `@AppStorage`'s own default (`false`) is what
        // this reads.
        let palette = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore
        )
        #expect(palette.usesModelBFieldForTesting == false)
    }

    // MARK: - Selector routing (acceptance criterion 4, see header note)

    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func makeTextView() -> ComposerGhostNSTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        return ComposerGhostNSTextView(frame: .zero, textContainer: container)
    }

    private func makeCoordinator(
        hasSelection: Bool,
        isPickerOpen: Bool,
        events: Box<[String]>
    ) -> (ComposerGhostTextField.Coordinator, ComposerGhostNSTextView) {
        let queryBox = Box("")
        let focusBox = Box(false)
        let field = ComposerGhostTextField(
            query: Binding(get: { queryBox.value }, set: { queryBox.value = $0 }),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: Binding(get: { focusBox.value }, set: { focusBox.value = $0 }),
            hasSelection: hasSelection,
            isPickerOpen: isPickerOpen,
            ghostFullPath: ""
        ) { event in
            switch event {
            case .exit: events.value.append("exit")
            case .submit: events.value.append("submit")
            case .submitNoMatch: events.value.append("submitNoMatch")
            case .move(.up): events.value.append("moveUp")
            case .move(.down): events.value.append("moveDown")
            default: events.value.append("moveOther")
            }
        }
        let coordinator = field.makeCoordinator()
        let textView = makeTextView()
        coordinator.textView = textView
        return (coordinator, textView)
    }

    @Test func insertNewlineWithSelectionDispatchesSubmit() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(handled == true)
        #expect(events.value == ["submit"])
    }

    @Test func insertNewlineWithoutSelectionDispatchesSubmitNoMatch() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: false, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(handled == true)
        #expect(events.value == ["submitNoMatch"])
    }

    @Test func insertNewlineWhilePickerOpenIsConsumedSilently() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: true, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(handled == true)
        #expect(events.value.isEmpty)
    }

    /// A-F10: unhandled `cancelOperation:` falls through to `complete:`
    /// (the word-completion panel). Asserting `true` here is the whole
    /// point of this test — `false` would leave an orphaned completion
    /// popup on screen (unverifiable from this test alone; see header).
    @Test func cancelOperationDispatchesExitAndReturnsTrue() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(handled == true)
        #expect(events.value == ["exit"])
    }

    @Test func moveUpDispatchesWhenPickerClosed() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveUp(_:)))
        #expect(handled == true)
        #expect(events.value == ["moveUp"])
    }

    @Test func moveDownDispatchesWhenPickerClosed() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveDown(_:)))
        #expect(handled == true)
        #expect(events.value == ["moveDown"])
    }

    @Test func moveUpIsConsumedSilentlyWhilePickerOpen() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: true, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveUp(_:)))
        #expect(handled == true)
        #expect(events.value.isEmpty)
    }

    @Test func moveDownIsConsumedSilentlyWhilePickerOpen() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: true, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveDown(_:)))
        #expect(handled == true)
        #expect(events.value.isEmpty)
    }

    /// No ghost label installed in this harness (`makeCoordinator` skips
    /// `installGhostLabel`) — Tab is a consumed no-op with nothing to
    /// accept. `tabAcceptsTheActiveSegmentGhost` below covers the actual
    /// accept path with a ghost label present.
    @Test func insertTabIsConsumedNoOpWithNoGhostLabel() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(handled == true)
        #expect(events.value.isEmpty)
    }

    /// 7b (Spotlight/Raycast rewrite): Tab accepts exactly ONE segment,
    /// preserving typed casing (G-F12 strawman) — `Gho` + accepted
    /// `stties > ` yields `Ghostties > `, not the whole remaining ghost
    /// (`currentGhostText` holds the FULL remainder now, per
    /// `remainderGhost`, not just the current segment).
    @Test func tabAcceptsExactlyOneSegmentLeavingTheRestGhosted() {
        let events = Box<[String]>([])
        let queryBox = Box("")
        let focusBox = Box(false)
        let field = ComposerGhostTextField(
            query: Binding(get: { queryBox.value }, set: { queryBox.value = $0 }),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: Binding(get: { focusBox.value }, set: { focusBox.value = $0 }),
            hasSelection: true,
            isPickerOpen: false,
            ghostFullPath: "Ghostties > Default > Orchestrator"
        ) { _ in }
        let coordinator = field.makeCoordinator()
        let textView = makeTextView()
        coordinator.textView = textView
        coordinator.installGhostLabel(in: textView)
        textView.string = "Gho"
        coordinator.applyStyles()
        // The ghost previews the FULL destination Return would commit, not
        // just the current segment's tail — this is what closes defect 1
        // (a truncated ghost that could disagree with what Return does).
        #expect(textView.currentGhostText == "stties > Default > Orchestrator")

        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(handled == true)
        #expect(textView.string == "Ghostties > ")
        #expect(queryBox.value == "Ghostties > ")

        // Second Tab: the ghost survived past the first accepted segment
        // (defect 2/3 — the old implementation dead-ended here, because
        // truncating the GHOST itself at the next separator meant a
        // post-accept remainder starting with " > " truncated to "").
        coordinator.applyStyles()
        #expect(textView.currentGhostText == "Default > Orchestrator")
        let secondHandled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(secondHandled == true)
        #expect(textView.string == "Ghostties > Default > ")

        // Third Tab accepts the final segment — no trailing separator left
        // to stop at, so the whole remainder is "one segment".
        coordinator.applyStyles()
        #expect(textView.currentGhostText == "Orchestrator")
        let thirdHandled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(thirdHandled == true)
        #expect(textView.string == "Ghostties > Default > Orchestrator")

        // Ghost is gone once typed text equals the full path — nothing
        // left for Tab or Return to add.
        coordinator.applyStyles()
        #expect(textView.currentGhostText == "")
    }

    // MARK: - Remainder ghost (pure function, previously `activeSegmentGhost`)

    @Test func remainderGhostReturnsWholePathWhenTypedIsEmpty() {
        let ghost = ComposerGhostTextField.remainderGhost(typed: "", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "Ghostties > Default > Orchestrator")
    }

    /// Defect 1/2 regression guard: the ghost must preview the FULL
    /// destination Return would commit, never truncated at the next
    /// segment separator — the old `activeSegmentGhostTruncatesAtNextSeparator`
    /// behavior this replaces is exactly the bug the brief calls out.
    @Test func remainderGhostReturnsTheWholeRemainderNotJustTheCurrentSegment() {
        let ghost = ComposerGhostTextField.remainderGhost(typed: "Gho", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "stties > Default > Orchestrator")
    }

    /// Defect 3 regression guard, direct: once a whole segment has been
    /// typed/accepted, the remainder STARTS with `" > "` — the old
    /// `activeSegmentGhost` truncated there and returned `""`, dead-ending
    /// Tab. This is the exact case named in the brief. Proven to fail
    /// against the pre-fix implementation (mutant check, see commit body).
    @Test func remainderGhostSurvivesWhenTypedEndsExactlyOnASegmentBoundary() {
        let ghost = ComposerGhostTextField.remainderGhost(typed: "Ghostties > ", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "Default > Orchestrator")
    }

    @Test func remainderGhostIsEmptyWhenTypedDivergesFromPrediction() {
        let ghost = ComposerGhostTextField.remainderGhost(typed: "xyz", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "")
    }

    @Test func remainderGhostIsEmptyWhenTypedIsTheWholePath() {
        let ghost = ComposerGhostTextField.remainderGhost(typed: "Ghostties > Default > Orchestrator", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "")
    }

    @Test func remainderGhostIsCaseInsensitive() {
        let ghost = ComposerGhostTextField.remainderGhost(typed: "gHO", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "stties > Default > Orchestrator")
    }

    // MARK: - Next segment (pure function, Tab's one-segment-at-a-time accept)

    @Test func nextSegmentStopsAtAndIncludesTheNextSeparator() {
        #expect(ComposerGhostTextField.nextSegment(remainder: "as > main > Shell") == "as > ")
    }

    @Test func nextSegmentIsTheWholeRemainderWhenNoSeparatorFollows() {
        #expect(ComposerGhostTextField.nextSegment(remainder: "Shell") == "Shell")
    }

    @Test func nextSegmentOfARemainderStartingOnABoundaryTakesTheSeparatorAndNextSegment() {
        #expect(ComposerGhostTextField.nextSegment(remainder: " > main > Shell") == " > main > ")
    }

    @Test func nextSegmentIsEmptyForAnEmptyRemainder() {
        #expect(ComposerGhostTextField.nextSegment(remainder: "") == "")
    }

    @Test func insertBacktabIsConsumedNoOp() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        #expect(handled == true)
        #expect(events.value.isEmpty)
    }

    @Test func unrecognizedSelectorReturnsFalse() {
        let events = Box<[String]>([])
        let (coordinator, textView) = makeCoordinator(hasSelection: true, isPickerOpen: false, events: events)
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.deleteForward(_:)))
        #expect(handled == false)
    }

    // MARK: - Defect 2 class: Tab-drill termination is a fixpoint property,
    // not a fixed-depth script (findings ledger F8)

    /// F8's kill: defect 2 was a NON-TERMINATION bug (Tab accepted one
    /// segment then the ghost died instead of advancing), and
    /// `tabAcceptsExactlyOneSegmentLeavingTheRestGhosted` above already
    /// proves it for a fixed 3-Tab, 3-segment path — bounded at whatever
    /// depth that test's author happened to type. This drives the two pure
    /// functions (`remainderGhost`/`nextSegment`, no mounting, no
    /// `Coordinator`) to a FIXPOINT for each of several path shapes: repeat
    /// "accept one segment" until the ghost goes empty, and assert it
    /// actually terminates within the path's own segment count and lands
    /// exactly on `fullPath`. A regression that dead-ends after N segments —
    /// for ANY N, not just whatever a hand-written script checked — fails
    /// this by simply never reaching `fullPath`.
    @Test(
        "repeated Tab-drill (remainderGhost + nextSegment) reaches a fixpoint at fullPath within its segment count",
        arguments: [
            "Ghostties",
            "Ghostties > Default > Orchestrator",
            "A > B > C > D > E",
            "Solo",
        ]
    )
    func tabDrillReachesFixpointAtFullPathWithinSegmentCount(fullPath: String) {
        let segmentCount = fullPath.components(separatedBy: ComposerGhostTextField.segmentSeparator).count

        var typed = ""
        var iterations = 0
        // Guard the loop itself against the exact failure mode this test
        // exists to catch — a dead ghost that never reaches `fullPath` would
        // otherwise spin here forever instead of failing.
        let maxIterations = segmentCount + 1

        while true {
            let ghost = ComposerGhostTextField.remainderGhost(typed: typed, fullPath: fullPath)
            guard !ghost.isEmpty else { break }

            iterations += 1
            #expect(
                iterations <= maxIterations,
                "Tab-drill on \"\(fullPath)\" did not reach a fixpoint within \(maxIterations) segments (stuck at typed=\"\(typed)\", ghost=\"\(ghost)\") — defect 2's non-termination class regressed"
            )
            guard iterations <= maxIterations else { break }

            let segment = ComposerGhostTextField.nextSegment(remainder: ghost)
            // `nextSegment` returning empty against a non-empty remainder is
            // itself the dead end defect 2 shipped — the old
            // `activeSegmentGhost` implementation produced exactly this
            // shape (remainder `" > B"`, next segment `""`) once a whole
            // segment had just been accepted.
            #expect(!segment.isEmpty, "nextSegment returned empty against a non-empty remainder \"\(ghost)\" — Tab has nothing left to accept even though \(fullPath) is not fully typed")
            guard !segment.isEmpty else { break }

            typed += segment
        }

        #expect(typed == fullPath, "Tab-drill on \"\(fullPath)\" settled at \"\(typed)\", not the full path")
        #expect(iterations <= segmentCount, "Tab-drill on \"\(fullPath)\" took \(iterations) Tabs for \(segmentCount) segments — expected at most one Tab per segment")
    }
}
