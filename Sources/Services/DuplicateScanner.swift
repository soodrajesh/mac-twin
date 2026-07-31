import Foundation

enum DuplicateScanner {
    struct Progress: Equatable {
        var filesScanned: Int
        var filesToHash: Int
        var filesHashed: Int
    }

    /// Recursively walks `roots`, buckets by size (free — a `stat`, no file
    /// content read) to eliminate files that can't possibly have a
    /// duplicate, then hashes only the survivors, concurrently, bounded to
    /// the machine's core count (hashing is CPU-bound once past the size
    /// filter, unlike `du`-based sizing elsewhere in this app family).
    static func scan(roots: [URL],
                      extensions: Set<String>? = nil,
                      isCancelled: @escaping () -> Bool,
                      onProgress: @escaping @Sendable (Progress) -> Void) -> [DuplicateGroup] {
        let candidates = enumerate(roots: roots, extensions: extensions)
        let bySize = Dictionary(grouping: candidates, by: { $0.size })
        let toHash = bySize.values.filter { $0.count > 1 }.flatMap { $0 }

        onProgress(Progress(filesScanned: candidates.count, filesToHash: toHash.count, filesHashed: 0))
        guard !toHash.isEmpty else { return [] }

        let lock = NSLock()
        var records: [FileRecord] = []
        var hashedCount = 0
        records.reserveCapacity(toHash.count)

        let queue = DispatchQueue(label: "dupefinder.hash", attributes: .concurrent)
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: max(1, ProcessInfo.processInfo.activeProcessorCount))

        for candidate in toHash {
            if isCancelled() { break }
            sem.wait()
            group.enter()
            queue.async {
                defer { sem.signal(); group.leave() }
                if !isCancelled(), let hash = HashService.sha256(of: candidate.url) {
                    let record = FileRecord(url: candidate.url, size: candidate.size, hash: hash, createdAt: candidate.createdAt)
                    lock.lock()
                    records.append(record)
                    hashedCount += 1
                    let snapshot = Progress(filesScanned: candidates.count, filesToHash: toHash.count, filesHashed: hashedCount)
                    lock.unlock()
                    onProgress(snapshot)
                }
            }
        }
        group.wait()

        return DuplicateGrouping.group(records)
    }

    private struct Candidate { let url: URL; let size: Int64; let createdAt: Date }

    private static func enumerate(roots: [URL], extensions: Set<String>?) -> [Candidate] {
        var out: [Candidate] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .creationDateKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let size = values.fileSize, size > 0, // empty files aren't meaningful "duplicates"
                      FileTypeFilter.matches(url, extensions: extensions) else { continue }
                out.append(Candidate(url: url, size: Int64(size), createdAt: values.creationDate ?? .distantPast))
            }
        }
        return out
    }
}
