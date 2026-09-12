import AppKit
import SwiftUI

/// System/Light/Dark, independent of the Mac's own appearance setting.
/// Template: mac-cleanup's `SettingsView.swift`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Small/Medium/Large/Extra Large — read via `Support.swift`'s
/// `\.textScale` environment key and applied by every view's
/// `.appFont(_:weight:)` call.
enum TextSizeSetting: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:      return "Small"
        case .medium:      return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .small:      return 0.9
        case .medium:      return 1.0
        case .large:      return 1.15
        case .extraLarge: return 1.3
        }
    }
}

/// How often a Pro scheduled scan re-runs.
enum ScheduledScanInterval: Int, CaseIterable, Identifiable {
    case daily = 24
    case every3Days = 72
    case weekly = 168

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily:       return "Daily"
        case .every3Days:  return "Every 3 Days"
        case .weekly:      return "Weekly"
        }
    }
}

/// The app's one Settings pane (⌘,). Template: mac-cleanup's
/// `SettingsView.swift` — Appearance, Text Size, then app-specific
/// preferences (Scanning), then License, then About, each its own tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ScanningTab()
                .tabItem { Label("Scanning", systemImage: "doc.on.doc") }
            LicenseTab()
                .tabItem { Label("License", systemImage: "checkmark.seal") }
            UpdatesTab()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 420)
    }
}

private struct AppearanceTab: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .appFont(.headline)
                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Text Size")
                    .appFont(.headline)
                Picker("", selection: $textSize) {
                    ForEach(TextSizeSetting.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Spacer()
        }
        .padding(20)
    }
}

private struct ScanningTab: View {
    @Environment(\.isProLicensed) private var isProLicensed
    @AppStorage("scheduledScansEnabled") private var scheduledScansEnabled = false
    @AppStorage("scheduledScanIntervalHours") private var scheduledScanIntervalHours = ScheduledScanInterval.daily.rawValue
    /// Mirrors `ExclusionStore.paths` in local `@State` — the store itself
    /// is a plain `UserDefaults` wrapper, not `ObservableObject`, so every
    /// add/remove here re-reads it back into this array to redraw the list.
    @State private var excludedPaths: [String] = ExclusionStore.paths
    @EnvironmentObject var model: DupeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan Scope")
                    .appFont(.headline)
                Text(isProLicensed
                     ? "Pro unlocked: scan any folder, no limit."
                     : "Free version scans Downloads, Pictures, Desktop, Documents, and Movies. Unlock Pro to add any custom folder.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Excluded Folders")
                        .appFont(.headline)
                    ProBadge()
                }
                Text("Never scanned, in any root you pick above.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)

                // A path excluded during a since-expired Pro period stays
                // visible and removable either way — Pro only gates adding
                // new exclusions, not un-gating ones already set.
                if excludedPaths.isEmpty {
                    Text("None").appFont(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(excludedPaths, id: \.self) { path in
                            HStack {
                                Text(URL(fileURLWithPath: path).abbreviatedPath)
                                    .appFont(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    ExclusionStore.remove(path)
                                    excludedPaths = ExclusionStore.paths
                                    model.rescan()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Stop excluding this folder")
                                .accessibilityLabel("Stop excluding this folder")
                            }
                        }
                    }
                }

                if isProLicensed {
                    Button("Add Folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Exclude"
                        if panel.runModal() == .OK, let url = panel.url {
                            ExclusionStore.add(url)
                            excludedPaths = ExclusionStore.paths
                            model.rescan()
                        }
                    }
                    .appFont(.callout)
                } else {
                    UnlockProButton(label: "Unlock Pro to Exclude Folders")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Scheduled Scans")
                        .appFont(.headline)
                    ProBadge()
                }
                Text("Automatically re-scan your last-used folders in the background, on a repeating schedule, while MacTwin is running.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)

                if isProLicensed {
                    Toggle("Enable scheduled scans", isOn: $scheduledScansEnabled)
                        .appFont(.body)
                    if scheduledScansEnabled {
                        Picker("Frequency", selection: $scheduledScanIntervalHours) {
                            ForEach(ScheduledScanInterval.allCases) { interval in
                                Text(interval.label).tag(interval.rawValue)
                            }
                        }
                        .appFont(.body)
                        .frame(maxWidth: 220)
                    }
                } else {
                    UnlockProButton(label: "Unlock Pro for Scheduled Scans")
                }
            }

            Spacer()
        }
        .padding(20)
    }
}

private struct LicenseTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LicenseManagementView()

            VStack(alignment: .leading, spacing: 6) {
                Text("MacTwin Pro unlocks:").appFont(.subheadline, weight: .semibold)
                ForEach([
                    "Scheduled background scans",
                    "Export scan reports (CSV)",
                    "Smart auto-select (beyond Keep Oldest)",
                    "Unlimited custom-folder scan scope",
                    "Exclude folders from scans",
                ], id: \.self) { line in
                    Text("• \(line)").appFont(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
    }
}

private struct UpdatesTab: View {
    @EnvironmentObject var model: DupeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

            if let update = model.availableUpdate {
                Text("MacTwin \(update.version) is available (you have \(currentVersion))")
                    .appFont(.callout)
                if let notes = update.notes, !notes.isEmpty {
                    Text(notes).appFont(.callout).foregroundStyle(.secondary)
                }
                Button("Get It") {
                    guard let url = URL(string: update.url) else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .appFont(.callout)
            } else {
                Text("You're on the latest version (\(currentVersion)).")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Check for Updates") { model.checkForUpdates() }
                .buttonStyle(.bordered)
                .appFont(.callout)

            Spacer()
        }
        .padding(20)
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            Text("MacTwin \(currentVersion)")
                .appFont(.headline)
            Text("A native macOS duplicate-file finder. Offline and private — every scan and hash happens locally.")
                .appFont(.callout)
                .foregroundStyle(.secondary)

            Button("Report a Bug or Request a Feature…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/soodrajesh/mac-twin/issues/new/choose")!)
            }
            .buttonStyle(.link)
            .appFont(.callout)

            Spacer()
        }
        .padding(20)
    }
}
