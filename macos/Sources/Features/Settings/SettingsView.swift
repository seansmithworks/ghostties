import SwiftUI

struct SettingsView: View {
    // We need access to our app delegate to know if we're quitting or not.
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        HStack {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text("Coming Soon. 🚧").font(.title)
                Text("Settings live in a Ghostty config file (any standard search path, e.g. $HOME/.config/ghostty/config). Edit it and restart Ghostties.")
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                Text("Update channel — beta (pre-release) or stable:")
                    .padding(.top, 6)
                Text("defaults write com.seansmithdesign.ghostties ghostties.autoUpdateChannel tip")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("defaults write com.seansmithdesign.ghostties ghostties.autoUpdateChannel stable")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("(\"tip\" is the beta feed.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 500, maxWidth: 500, minHeight: 156, maxHeight: 156)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
