import AppKit

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    /// The full path with the home directory collapsed to `~`, so every
    /// item row can show exactly where a file lives without the noise of a
    /// long absolute path.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
