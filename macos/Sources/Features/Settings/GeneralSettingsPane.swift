import SwiftUI

/// Settings > General: the update channel and the config file. The channel
/// is the same `ghostties.autoUpdateChannel` default `defaults write` set
/// (`Ghostty.Config.autoUpdateChannel` reads it from `.standard`, which
/// `AppDefaults.store` is outside tests, at each update check); with
/// none stored the picker shows what the config resolves to.
struct GeneralSettingsPane: View {
    static let channelKey = "ghostties.autoUpdateChannel"

    @AppStorage(GeneralSettingsPane.channelKey, store: AppDefaults.store) private var storedChannel: String?

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    private var channel: Binding<Ghostty.AutoUpdateChannel> {
        Binding(
            get: {
                storedChannel.flatMap(Ghostty.AutoUpdateChannel.init(rawValue:))
                    ?? appDelegate?.ghostty.config.autoUpdateChannel
                    ?? .tip
            },
            set: { storedChannel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Update channel", selection: channel) {
                    Text("Beta").tag(Ghostty.AutoUpdateChannel.tip)
                    Text("Stable").tag(Ghostty.AutoUpdateChannel.stable)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Beta gets pre-release builds first. Stable gets only full releases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Config file") {
                    Button("Open Config File") { appDelegate?.ghostty.openConfig() }
                }
            } footer: {
                Text("Everything else lives in a Ghostty config file (any standard path, e.g. ~/.config/ghostty/config). Edit it and reload the config.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
