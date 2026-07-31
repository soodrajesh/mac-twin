import Foundation

/// Pure grouping logic, kept separate from `DuplicateScanner`'s filesystem
/// walk/hashing so it can be tested directly against in-memory records.
enum DuplicateGrouping {
    /// Buckets records by size, then by hash within each size bucket — a
    /// hash collision across different sizes is impossible so size alone
    /// already partitions correctly; hash only needs to split ties within it.
    /// Groups of 1 (nothing else shares that size+hash) are dropped.
    static func group(_ records: [FileRecord]) -> [DuplicateGroup] {
        let bySize = Dictionary(grouping: records, by: { $0.size })
        var groups: [DuplicateGroup] = []
        for (size, sameSize) in bySize where sameSize.count > 1 {
            let byHash = Dictionary(grouping: sameSize, by: { $0.hash })
            for (hash, sameHash) in byHash where sameHash.count > 1 {
                // Suggested keeper: oldest by creation date, ties broken by
                // the shortest path — usually the more "original" copy
                // rather than one nested in a Downloads/Copy subfolder.
                let sorted = sameHash.sorted { a, b in
                    if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                    return a.url.path.count < b.url.path.count
                }
                groups.append(DuplicateGroup(hash: hash, size: size, items: sorted))
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }
}
