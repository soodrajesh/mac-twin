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
        let candidates = enumerate(roots: roots, extensions: extensions, isCancelled: isCancelled, onProgress: onProgress)
        if isCancelled() { return [] }
        let bySize = Dictionary(grouping: candidates, by: { $0.size })
        let toHash = bySize.values.filter { $0.count > 1 }.flatMap { $0 }

        onProgress(Progress(filesScanned: candidates.count, filesToHash: toHash.count, filesHashed: 0))
        guard !toHash.isEmpty else { return [] }

        let lock = NSLock()
        var records: [FileRecord] = []
        var hashedCount = 0
        records.reserveCapacity(toHash.count)

        // .utility (not .default/.unspecified): hashing is bulk, non-interactive
        // work — at full core-count concurrency an unspecified QoS competes
        // evenly with the UI and other apps' interactive work for CPU time,
        // which is what made a scan feel like the whole Mac was hanging.
        // .utility tells the scheduler to yield to interactive/user-initiated
        // work under contention instead.
        let queue = DispatchQueue(label: "mactwin.hash", qos: .utility, attributes: .concurrent)
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

    /// Walks each root independently (roots can legitimately be disjoint
    /// folders), but de-duplicates by *canonical* path across every root
    /// combined before returning. This is the safety net for overlapping or
    /// nested user-picked roots (e.g. `~/Desktop` and `~/Desktop/Work` both
    /// checked, or a symlink pointing back into an already-scanned tree):
    /// without it, the same physical file gets enumerated twice under two
    /// `Candidate` entries that share the same resolved URL, and downstream
    /// grouping would present a file's *only* copy as a "duplicate" of
    /// itself. Resolving symlinks + standardizing also catches the
    /// symlink-driven variant of the same problem, not just literal
    /// double-checked folders. This is the primary fix (robust regardless of
    /// UI-level containment checks); see also `StartView.chooseFolder()`'s
    /// containment check as a secondary, earlier warning.
    /// Checks `isCancelled` and emits `onProgress` periodically during the
    /// walk itself (not only once after it fully completes) — on a deep or
    /// slow (e.g. network-volume) tree, pressing Cancel now takes effect
    /// promptly instead of only after enumeration finishes, and the
    /// "Scanning…" screen gets a live count instead of sitting static.
    private static func enumerate(roots: [URL],
                                   extensions: Set<String>?,
                                   isCancelled: @escaping () -> Bool,
                                   onProgress: @escaping @Sendable (Progress) -> Void) -> [Candidate] {
        var out: [Candidate] = []
        var seenCanonicalPaths = Set<String>()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .creationDateKey]
        let progressInterval = 200
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if isCancelled() { return out }
                // Skip the whole subtree, not just this entry — cheaper than
                // walking into a large excluded folder only to filter every
                // file back out one by one, and correct whether `url` here
                // is the excluded directory itself or a file inside it.
                if ExclusionStore.isExcluded(url) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let size = values.fileSize, size > 0, // empty files aren't meaningful "duplicates"
                      FileTypeFilter.matches(url, extensions: extensions) else { continue }
                let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard seenCanonicalPaths.insert(canonicalPath).inserted else { continue }
                out.append(Candidate(url: url, size: Int64(size), createdAt: values.creationDate ?? .distantPast))
                if out.count % progressInterval == 0 {
                    onProgress(Progress(filesScanned: out.count, filesToHash: 0, filesHashed: 0))
                }
            }
        }
        return out
    }
}
