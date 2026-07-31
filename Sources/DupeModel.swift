import Foundation

@MainActor
final class DupeModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var scanProgress: DuplicateScanner.Progress?
    @Published var hasScanned = false

    /// Flat set of files checked for trashing, keyed by URL rather than by
    /// group — a plain toggle with no "must keep one" bookkeeping needed,
    /// since Trash is always recoverable.
    @Published var selectedForTrash: Set<URL> = []

    @Published var isDeleting = false
    @Published var deletionProgress: (done: Int, total: Int)?
    @Published var lastError: String?

    private var scanTask: Task<Void, Never>?

    var totalWastedBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    var selectedBytes: Int64 {
        groups.reduce(0) { total, group in
            total + group.items.filter { selectedForTrash.contains($0.url) }.reduce(0) { $0 + $1.size }
        }
    }

    func startScan(roots: [URL], extensions: Set<String>? = nil) {
        scanTask?.cancel()
        groups = []
        selectedForTrash = []
        scanProgress = nil
        lastError = nil
        isScanning = true
        hasScanned = false

        scanTask = Task.detached { [weak self] in
            guard let self else { return }
            let result = DuplicateScanner.scan(
                roots: roots,
                extensions: extensions,
                isCancelled: { Task.isCancelled },
                onProgress: { progress in
                    Task { @MainActor in self.scanProgress = progress }
                })
            await MainActor.run {
                self.groups = result
                self.selectedForTrash = Set(result.flatMap { group in
                    group.items.enumerated().compactMap { i, item in i == group.keeperIndex ? nil : item.url }
                })
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    func toggleSelection(_ url: URL) {
        if selectedForTrash.contains(url) {
            selectedForTrash.remove(url)
        } else {
            selectedForTrash.insert(url)
        }
    }

    func moveSelectedToTrash(completion: @escaping () -> Void) {
        let urls = Array(selectedForTrash)
        guard !urls.isEmpty else { return }
        isDeleting = true
        deletionProgress = (0, urls.count)

        Task.detached { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            TrashService.moveToTrash(urls, isCancelled: { false }) { i, outcome in
                if !outcome.success, let error = outcome.error {
                    failures.append("\(outcome.url.lastPathComponent): \(error)")
                }
                Task { @MainActor in self.deletionProgress = (i + 1, urls.count) }
            }
            let failureMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
            await MainActor.run {
                self.removeTrashed(urls)
                self.isDeleting = false
                self.deletionProgress = nil
                self.lastError = failureMessage
                completion()
            }
        }
    }

    /// Drops trashed files from their groups; a group left with fewer than
    /// 2 copies is no longer a duplicate set and is removed entirely.
    private func removeTrashed(_ urls: [URL]) {
        let trashed = Set(urls)
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !trashed.contains($0.url) }
            guard remaining.count > 1 else { return nil }
            return DuplicateGroup(hash: group.hash, size: group.size, items: remaining)
        }
        selectedForTrash.subtract(trashed)
    }
}
