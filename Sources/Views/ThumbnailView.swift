import SwiftUI
import QuickLookThumbnailing

/// Renders a thumbnail for any file Quick Look understands — images, PDFs,
/// videos, and more — through one API, instead of special-casing image
/// files vs. everything else.
struct ThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            image = await Self.generate(for: url, size: size)
        }
    }

    private static func generate(for url: URL, size: CGFloat) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: scale, representationTypes: .thumbnail)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep.map { NSImage(cgImage: $0.cgImage, size: CGSize(width: size, height: size)) })
            }
        }
    }
}
