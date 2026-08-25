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

    /// 7b: Tab accepts the active-segment ghost, preserving typed casing
    /// (G-F12 strawman) — `Gho` + accepted `stties` yields `Ghostties`.
    @Test func tabAcceptsTheActiveSegmentGhost() {
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
        #expect(textView.currentGhostText == "stties")

        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(handled == true)
        #expect(textView.string == "Ghostties")
        #expect(queryBox.value == "Ghostties")
    }

    // MARK: - Active-segment ghost (pure function)

    @Test func activeSegmentGhostReturnsWholePathWhenTypedIsEmpty() {
        let ghost = ComposerGhostTextField.activeSegmentGhost(typed: "", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "Ghostties > Default > Orchestrator")
    }

    @Test func activeSegmentGhostTruncatesAtNextSeparator() {
        let ghost = ComposerGhostTextField.activeSegmentGhost(typed: "Gho", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "stties")
    }

    @Test func activeSegmentGhostIsEmptyWhenTypedDivergesFromPrediction() {
        let ghost = ComposerGhostTextField.activeSegmentGhost(typed: "xyz", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "")
    }

    @Test func activeSegmentGhostIsEmptyWhenTypedIsTheWholePath() {
        let ghost = ComposerGhostTextField.activeSegmentGhost(typed: "Ghostties > Default > Orchestrator", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "")
    }

    @Test func activeSegmentGhostIsCaseInsensitive() {
        let ghost = ComposerGhostTextField.activeSegmentGhost(typed: "gHO", fullPath: "Ghostties > Default > Orchestrator")
        #expect(ghost == "stties")
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
}
