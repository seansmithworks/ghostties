import AppKit
import Darwin
import SwiftUI

/// `@AppStorage` key gating the dev build-info badge. Default ON in Debug
/// builds, OFF in Release. Toggle manually with:
///
///   defaults write com.seansmithdesign.ghostties.dev ghostties.devBuildInfoBadge.enabled -bool true
///   defaults write com.seansmithdesign.ghostties.dev ghostties.devBuildInfoBadge.enabled -bool false
///   defaults write com.seansmithdesign.ghostties ghostties.devBuildInfoBadge.enabled -bool true
///   defaults write com.seansmithdesign.ghostties ghostties.devBuildInfoBadge.enabled -bool false
private let buildInfoBadgeStorageKey = "ghostties.devBuildInfoBadge.enabled"

#if DEBUG
    private let buildInfoBadgeDefaultEnabled = true
#else
    private let buildInfoBadgeDefaultEnabled = false
#endif

/// One-time snapshot of build and launch facts, resolved at runtime from the
/// bundle and the process table — no baked-in git SHA, no Xcode build phase.
/// See `reference_stale-dev-instance-serves-old-code.md`: a running instance
/// keeps serving the binary it launched with, so "is this the latest build"
/// requires comparing binary mtime against process launch time.
struct BuildInfoSnapshot {
    let shortVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let buildDate: Date?
    let launchDate: Date

    /// Resolved once per process.
    static let current: BuildInfoSnapshot = {
        let bundle = Bundle.main
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bundleIdentifier = bundle.bundleIdentifier ?? "?"

        var buildDate: Date?
        if let execURL = bundle.executableURL,
            let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
            let modDate = attrs[.modificationDate] as? Date
        {
            buildDate = modDate
        }

        return BuildInfoSnapshot(
            shortVersion: shortVersion,
            buildNumber: buildNumber,
            bundleIdentifier: bundleIdentifier,
            buildDate: buildDate,
            launchDate: BuildInfoSnapshot.currentProcessStartDate()
        )
    }()

    /// Exact process launch time via `sysctl(KERN_PROC_PID)` — the same value
    /// `ps -o lstart` reports. Falls back to "now" if the sysctl call fails.
    private static func currentProcessStartDate() -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return Date() }
        let ts = info.kp_proc.p_starttime
        let seconds = TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let fullTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    /// Glanceable one-liner for the always-visible label.
    var shortLabel: String {
        let builtText = buildDate.map { Self.shortTimeFormatter.string(from: $0) } ?? "?"
        let upText = Self.durationFormatter.string(from: launchDate, to: Date()) ?? "0m"
        return "\(shortVersion) (\(buildNumber)) · built \(builtText) · up \(upText)"
    }

    /// Full multi-line detail copied to the pasteboard on click.
    var fullDetail: String {
        let builtText = buildDate.map { Self.fullTimeFormatter.string(from: $0) } ?? "unknown"
        let launchText = Self.fullTimeFormatter.string(from: launchDate)
        let upText = Self.durationFormatter.string(from: launchDate, to: Date()) ?? "0m"
        return """
            Ghostties build info
            Version: \(shortVersion) (\(buildNumber))
            Bundle: \(bundleIdentifier)
            Built: \(builtText)
            Launched: \(launchText) (running \(upText))
            """
    }
}

/// Tiny diagnostic label pinned to the bottom-left corner of the window.
/// Answers "is this the latest build, and when did this instance start" at a
/// glance; click copies the full detail to the pasteboard. Sizes itself to
/// its content (`.fixedSize()`) so it never intercepts clicks outside its
/// own bounds — it must not swallow terminal clicks.
struct BuildInfoBadgeView: View {
    @AppStorage(buildInfoBadgeStorageKey) private var isEnabled: Bool = buildInfoBadgeDefaultEnabled
    @State private var justCopied = false
    @Environment(\.colorScheme) private var colorScheme

    private let info = BuildInfoSnapshot.current

    var body: some View {
        if isEnabled {
            Text(justCopied ? "Copied build info" : info.shortLabel)
                .font(.system(size: 9))
                .foregroundColor(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(perform: copyToPasteboard)
                .help(info.fullDetail)
                .fixedSize()
        }
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info.fullDetail, forType: .string)

        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            justCopied = false
        }
    }
}
