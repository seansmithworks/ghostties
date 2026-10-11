#if DEBUG
import DialkitmacOS
import DialkitmacOSProtocol
import Foundation
import Testing
@testable import Ghostty

/// The Rail panel's "Rail tiles" dials, set the way the inspector sets
/// them (through the panel state's values), persist a key and change what
/// the morph rail reads.
@MainActor
struct RailTileDialsTests {
    struct Case: CustomTestStringConvertible {
        let name: String
        let key: String
        let set: (inout RailDialKitTuningModel) -> Void
        let read: (SidebarMorphMetrics.Dials) -> CGFloat
        let expected: CGFloat
        var testDescription: String { name }
    }

    private static let cases: [Case] = [
        Case(name: "Project tile size", key: SidebarDialTuning.railProjectTileSizeKey,
             set: { $0.railProjectTileSize = 31 }, read: \.railTileSize, expected: 31),
        Case(name: "Project tile text", key: SidebarDialTuning.railProjectTileTextKey,
             set: { $0.railProjectTileText = 13 }, read: \.railTileText, expected: 13),
        Case(name: "Thread tile size", key: SidebarDialTuning.railThreadTileSizeKey,
             set: { $0.railThreadTileSize = 29 }, read: \.railChipSize, expected: 29),
        Case(name: "Thread tile icon", key: SidebarDialTuning.railThreadTileIconKey,
             set: { $0.railThreadTileIcon = 19 }, read: \.railGlyphSize, expected: 19),
    ]

    @Test(arguments: cases)
    func railTileDialDrivesTheMorphRail(_ c: Case) {
        withDials({ _ in }) {
            let defaults = SidebarDialTuning.store
            let coordinator = FocusedDialKitCoordinator<RailDialPanel>(defaults: defaults, onChange: {})
            #expect(defaults.object(forKey: c.key) == nil)
            #expect(c.read(.current(defaults: defaults)) != c.expected)

            c.set(&coordinator.state.values)

            #expect(defaults.object(forKey: c.key) != nil, "\(c.name) persisted no key")
            #expect(c.read(.current(defaults: defaults)) == c.expected, "\(c.name) did not reach the morph rail")
        }
    }

    /// The inspector's route: a remote `setControlValue` addressed by the
    /// panel's id and the control's path from the published snapshot.
    @Test(arguments: cases)
    func remoteEditDrivesTheMorphRail(_ c: Case) throws {
        try withDials({ _ in }) {
            let defaults = SidebarDialTuning.store
            let coordinator = FocusedDialKitCoordinator<RailDialPanel>(defaults: defaults, onChange: {})
            let panel = try #require(
                DialStore.shared.remoteSnapshot(appName: "t").panels.first { $0.id == coordinator.state.id }
            )
            func find(_ controls: [DialKitControlSnapshot]) -> DialKitControlSnapshot? {
                for control in controls {
                    if control.label == c.name { return control }
                    if case let .group(_, children) = control.kind, let hit = find(children) { return hit }
                }
                return nil
            }
            let control = try #require(find(panel.controls), "no \(c.name) control in the Rail panel")
            #expect(DialStore.shared.setRemoteControlValue(panelID: coordinator.state.id, path: control.path, value: .number(Double(c.expected))))

            #expect(defaults.object(forKey: c.key) != nil, "\(c.name) persisted no key")
            #expect(c.read(.current(defaults: defaults)) == c.expected, "\(c.name) did not reach the morph rail")
        }
    }
}
#endif
