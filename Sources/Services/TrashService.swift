import Foundation

/// Moves items to macOS Trash — recoverable until it's emptied. This app
/// never calls `removeItem`; there's no "empty Trash" feature here to need it.
enum TrashService {
    struct DeletionOutcome {
        let url: URL
        let success: Bool
        let error: String?
    }

    /// Trashes each URL in turn. A failure on one item (permission denied,
    /// file in use) is reported and the batch continues — it must never
    /// abort the whole run.
    static func moveToTrash(_ urls: [URL],
                             isCancelled: @escaping () -> Bool,
                             perItem: @escaping (Int, DeletionOutcome) -> Void) {
        for (i, url) in urls.enumerated() {
            if isCancelled() { break }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                perItem(i, DeletionOutcome(url: url, success: true, error: nil))
            } catch {
                perItem(i, DeletionOutcome(url: url, success: false, error: error.localizedDescription))
            }
        }
    }
}
