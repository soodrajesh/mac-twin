import SwiftUI
import AppKit

/// How the duplicate-set list is ordered. Purely a display concern — it
/// never touches `model.groups` itself, so selection/trash state (keyed by
/// group id) is unaffected by re-sorting.
enum ResultsSortOption: String, CaseIterable, Identifiable {
    case size = "Size"
    case name = "Name"
    case date = "Date"
    var id: String { rawValue }
}

struct ResultsView: View {
    @EnvironmentObject var model: DupeModel
    @Environment(\.isProLicensed) private var isProLicensed
    @State private var showConfirm = false
    @State private var exportError: String?
    @State private var sortOption: ResultsSortOption = .size

    private var sortedGroups: [DuplicateGroup] {
        switch sortOption {
        case .size:
            // Matches DuplicateGrouping's own default order (most space
            // reclaimed first) — the common "what's actually worth reviewing"
            // ordering, kept as the default.
            return model.groups.sorted { $0.wastedBytes > $1.wastedBytes }
        case .name:
            return model.groups.sorted {
                $0.keeper.url.lastPathComponent.localizedStandardCompare($1.keeper.url.lastPathComponent) == .orderedAscending
            }
        case .date:
            // Newest keeper first — surfaces recently-created duplicate sets,
            // e.g. ones from a scan you just ran versus long-settled ones.
            return model.groups.sorted { $0.keeper.createdAt > $1.keeper.createdAt }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar

            if model.groups.isEmpty {
                VStack(spacing: 10) {
                    IconTile(systemName: "checkmark.circle", tint: .green, size: 56)
                        .accessibilityHidden(true)
                    Text("No duplicates found")
                        .appFont(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(sortedGroups) { group in
                            GroupRowView(group: group)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding()
                }
            }

            footer
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.groups = []
                    model.hasScanned = false
                } label: {
                    Label("New Scan", systemImage: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                if !model.groups.isEmpty {
                    sortMenu
                    autoSelectMenu
                    exportButton
                }
            }
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmDeletionSheet(isPresented: $showConfirm)
        }
        .alert("Couldn't Export Report", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.groups.count)
    }

    private var summaryBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !model.groups.isEmpty {
                    Text(model.totalWastedBytes.humanBytes)
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(Color.appAccent)
                    Text("reclaimable across \(model.groups.count) duplicate sets")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !model.groups.isEmpty {
                Text("We've pre-selected every copy except the oldest in each set for deletion — review before confirming.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(ResultsSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Label("Sort: \(sortOption.rawValue)", systemImage: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder
    private var autoSelectMenu: some View {
        if isProLicensed {
            Menu {
                ForEach(AutoSelectStrategy.allCases) { strategy in
                    Button(strategy.rawValue) { model.applyAutoSelect(strategy) }
                }
            } label: {
                Label("Smart Select", systemImage: "wand.and.stars")
            }
        } else {
            UnlockProButton(label: "Smart Select")
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if isProLicensed {
            Button {
                exportReport()
            } label: {
                Label("Export Report", systemImage: "square.and.arrow.up")
            }
        } else {
            UnlockProButton(label: "Export Report")
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacTwin-Report.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportReport(to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var footer: some View {
        HStack {
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .appFont(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            let count = model.selectedForTrash.count
            Button {
                showConfirm = true
            } label: {
                Text(count == 0 ? "Move Selected to Trash" : "Move \(count) to Trash (\(model.selectedBytes.humanBytes))")
                    .appFont(.body, weight: .semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(count == 0)
        }
        .padding()
    }
}

struct ScanningView: View {
    @EnvironmentObject var model: DupeModel

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.appAccent)
            if let progress = model.scanProgress {
                Text(progress.filesToHash > 0
                     ? "Hashing \(progress.filesHashed) / \(progress.filesToHash) candidates…"
                     : "Scanned \(progress.filesScanned) files…")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("Scanning folders…")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") { model.cancelScan() }
                .appFont(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
