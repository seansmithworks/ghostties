import AppKit
import SwiftUI

/// First-launch welcome sheet. Presented once, on fresh install, over the
/// sidebar in any mode (`onboardingSheet()`). Dismissed via the "Get started" button, after which
/// `ghostties.hasSeenOnboarding` is set so it never appears again.
@MainActor
struct OnboardingSheet: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let buildVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }()

    private let buildNumber: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }()

    private let buildDate: String = {
        guard let execPath = Bundle.main.executablePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return "Unknown"
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        fmt.locale = Locale(identifier: "en_US")
        return fmt.string(from: modDate)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Use the sidebar to manage multiple repos, agent threads, and terminals — all in one window.")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)

                    Text("Built on top of Ghostty.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Text("Ghostties is in active development. Features may change.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Feedback:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Link("sean@seansmithdesign.com", destination: URL(string: "mailto:sean@seansmithdesign.com?subject=Ghostties%20Feedback")!)
                                .font(.system(size: 12))
                        }

                        HStack(spacing: 4) {
                            Text("GitHub:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Link("github.com/SeanSmithWorks/ghostties", destination: URL(string: "https://github.com/SeanSmithWorks/ghostties")!)
                                .font(.system(size: 12))
                        }
                    }

                    Text("Version \(buildVersion) (build \(buildNumber)) · Updated \(buildDate)")
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .frame(width: 420, height: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome to Ghostties")
                .font(.system(size: 14, weight: .semibold))

            Text("Ghostty + workspace + agents")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Get started") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

extension View {
    /// Presents `OnboardingSheet` until `ghostties.hasSeenOnboarding` is set.
    /// Applied to the sidebar in every mode (project-first and task-first), so
    /// first run never depends on which mode the sidebar is in. The demo and
    /// capture builds suppress it by launching with
    /// `-ghostties.hasSeenOnboarding YES`.
    func onboardingSheet() -> some View {
        modifier(OnboardingSheetModifier())
    }
}

private struct OnboardingSheetModifier: ViewModifier {
    @AppStorage("ghostties.hasSeenOnboarding") private var hasSeenOnboarding = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in }
        )) {
            OnboardingSheet {
                hasSeenOnboarding = true
            }
        }
    }
}
