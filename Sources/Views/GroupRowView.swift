import SwiftUI
import AppKit

struct GroupRowView: View {
    let group: DuplicateGroup
    @EnvironmentObject var model: DupeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(group.items.count)")
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(Color.appAccent)
                    Text("copies · \(group.size.humanBytes) each")
                        .appFont(.subheadline, weight: .semibold)
                }
                Spacer()
                Text("wastes \(group.wastedBytes.humanBytes)")
                    .appFont(.subheadline, weight: .bold)
                    .foregroundStyle(.orange)
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
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
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
                        .foregroundStyle(isSelected ? Color.appAccent : Color.secondary)
                        .background(Circle().fill(.background).padding(1))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .help(isSelected ? "Selected for Trash" : "Not selected for Trash")
                .accessibilityLabel(isSelected ? "Selected for Trash" : "Not selected for Trash")
                .accessibilityAddTraits(.isButton)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
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
