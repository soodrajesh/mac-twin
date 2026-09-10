import SwiftUI
import AppKit

struct GroupRowView: View {
    let group: DuplicateGroup
    @EnvironmentObject var model: DupeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.items.count) copies · \(group.size.humanBytes) each")
                    .appFont(.subheadline, weight: .bold)
                Spacer()
                Text("wastes \(group.wastedBytes.humanBytes)")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(group.items.enumerated()), id: \.element.url) { index, item in
                        ItemCard(item: item, isKeeperSuggestion: index == group.keeperIndex)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ItemCard: View {
    let item: FileRecord
    let isKeeperSuggestion: Bool
    @EnvironmentObject var model: DupeModel

    private var isSelected: Bool { model.selectedForTrash.contains(item.url) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: item.url, size: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isKeeperSuggestion ? Color.green : Color.clear, lineWidth: 2)
                    )
                Button {
                    model.toggleSelection(item.url)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .background(Circle().fill(.background).padding(1))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }

            if isKeeperSuggestion {
                Text("Suggested keep")
                    .appFont(.caption2, weight: .bold)
                    .foregroundStyle(.green)
            }

            Text(item.url.lastPathComponent)
                .appFont(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.url.deletingLastPathComponent().abbreviatedPath)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(width: 120)
        .help(item.url.abbreviatedPath) // full path on hover — the card truncates it
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(item.url) }
            Button("Copy Path") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.url.path, forType: .string)
            }
        }
        .onTapGesture(count: 2) { revealInFinder(item.url) }
    }
}
