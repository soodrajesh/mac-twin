import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var model: DupeModel
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No duplicates found")
                        .font(.headline)
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
        .sheet(isPresented: $showConfirm) {
            ConfirmDeletionSheet(isPresented: $showConfirm)
        }
    }

    private var header: some View {
        HStack {
            Button {
                model.groups = []
                model.hasScanned = false
            } label: {
                Label("New Scan", systemImage: "chevron.left")
            }
            Spacer()
            if !model.groups.isEmpty {
                Text("\(model.groups.count) duplicate sets · \(model.totalWastedBytes.humanBytes) reclaimable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            let count = model.selectedForTrash.count
            Button {
                showConfirm = true
            } label: {
                Text(count == 0 ? "Move Selected to Trash" : "Move \(count) to Trash (\(model.selectedBytes.humanBytes))")
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
                    .foregroundStyle(.secondary)
            } else {
                Text("Scanning folders…")
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
