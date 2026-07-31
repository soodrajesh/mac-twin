import Foundation

/// Preset file-type groupings for the scan filter, plus the extensions each
/// one covers. Kept as data (not tied to any scanning logic) so it's usable
/// from both the UI and the scanner without a dependency in either direction.
enum FileCategory: String, CaseIterable, Identifiable {
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"

    var id: String { rawValue }

    var extensions: Set<String> {
        switch self {
        case .images: return ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "raw", "dng"]
        case .videos: return ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm"]
        case .audio: return ["mp3", "wav", "aac", "m4a", "flac", "aiff", "ogg"]
        case .documents: return ["pdf", "doc", "docx", "txt", "rtf", "pages", "key", "ppt", "pptx", "xls", "xlsx", "csv", "md"]
        }
    }
}

/// `nil`/empty extension set means "no filter, include everything" — kept as
/// a standalone pure function so it's testable without touching the filesystem.
enum FileTypeFilter {
    static func matches(_ url: URL, extensions: Set<String>?) -> Bool {
        guard let extensions, !extensions.isEmpty else { return true }
        return extensions.contains(url.pathExtension.lowercased())
    }
}
