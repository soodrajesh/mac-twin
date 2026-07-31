import SwiftUI

struct ConfirmDeletionSheet: View {
    @EnvironmentObject var model: DupeModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            if let progress = model.deletionProgress {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                Text("Moving \(progress.done) / \(progress.total) to Trash…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "trash")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Move \(model.selectedForTrash.count) files to Trash?")
                    .font(.headline)
                Text("\(model.selectedBytes.humanBytes) will be reclaimed. Files go to Trash, recoverable until you empty it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("Cancel") { isPresented = false }
                    Button("Move to Trash") {
                        model.moveSelectedToTrash { isPresented = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(24)
        .frame(width: 340)
        .interactiveDismissDisabled(model.deletionProgress != nil)
    }
}
