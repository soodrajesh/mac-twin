import SwiftUI

struct ConfirmDeletionSheet: View {
    @EnvironmentObject var model: DupeModel
    @Binding var isPresented: Bool

    /// Explicit override required before "Move to Trash" is enabled when
    /// the pending selection would leave one or more groups with zero
    /// surviving copies (see `DupeModel.groupsWithNoSurvivors`).
    @State private var acknowledgedNoSurvivors = false

    private var noSurvivorGroups: [DuplicateGroup] { model.groupsWithNoSurvivors }

    /// Every selected file, grouped by duplicate set, for the itemized list
    /// below — so a user reviewing a large batch can see exactly what's
    /// about to be trashed rather than only an aggregate count.
    private var selectedItemsByGroup: [(group: DuplicateGroup, items: [FileRecord])] {
        model.groups.compactMap { group in
            let selected = group.items.filter { model.selectedForTrash.contains($0.url) }
            return selected.isEmpty ? nil : (group, selected)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let progress = model.deletionProgress {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .tint(.red)
                Text("Moving \(progress.done) / \(progress.total) to Trash…")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            } else {
                IconTile(systemName: "trash", tint: .red, size: 48)
                    .accessibilityHidden(true)
                Text("Move \(model.selectedForTrash.count) files to Trash?")
                    .appFont(.headline)
                Text("\(model.selectedBytes.humanBytes) will be reclaimed. Files go to Trash, recoverable until you empty it.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                itemizedList

                if !noSurvivorGroups.isEmpty {
                    noSurvivorWarning
                }

                HStack {
                    Button("Cancel") { isPresented = false }
                        .appFont(.body)
                        .keyboardShortcut(.cancelAction)
                    Button("Move to Trash") {
                        model.moveSelectedToTrash { isPresented = false }
                    }
                    .appFont(.body)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!noSurvivorGroups.isEmpty && !acknowledgedNoSurvivors)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled(model.deletionProgress != nil)
    }

    private var itemizedList: some View {
        DisclosureGroup("Review \(model.selectedForTrash.count) files") {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(selectedItemsByGroup, id: \.group.id) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(entry.items, id: \.url) { item in
                                HStack {
                                    Text(item.url.abbreviatedPath)
                                        .appFont(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(item.size.humanBytes)
                                        .appFont(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 200)
        }
        .appFont(.callout)
    }

    private var noSurvivorWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This would delete every copy of \(noSurvivorGroups.count == 1 ? "1 file" : "\(noSurvivorGroups.count) files") — nothing would remain.", systemImage: "exclamationmark.triangle.fill")
                .appFont(.callout, weight: .bold)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(noSurvivorGroups.prefix(5)) { group in
                    Text("• \(group.keeper.url.lastPathComponent) (\(group.items.count) copies, all selected)")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                if noSurvivorGroups.count > 5 {
                    Text("…and \(noSurvivorGroups.count - 5) more")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("I understand — delete every copy of these files anyway", isOn: $acknowledgedNoSurvivors)
                .appFont(.callout)
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
