import SwiftUI
import AppKit

struct ResultsView: View {
    @EnvironmentObject var model: DupeModel
    @Environment(\.isProLicensed) private var isProLicensed
    @State private var showConfirm = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            summaryBar

            if model.groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No duplicates found")
                        .appFont(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.groups) { group in
                            GroupRowView(group: group)
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
    }

    private var summaryBar: some View {
        HStack {
            if !model.groups.isEmpty {
                Text("\(model.groups.count) duplicate sets · \(model.totalWastedBytes.humanBytes) reclaimable")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
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
        panel.nameFieldStringValue = "DupeFinder-Report.csv"
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
                    .appFont(.body)
            }
            .buttonStyle(.borderedProminent)
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
