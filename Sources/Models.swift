import Foundation

/// One file on disk, sized and hashed. `hash` is only ever populated for
/// files whose size collided with at least one other file — see
/// `DuplicateScanner`.
struct FileRecord: Equatable {
    let url: URL
    let size: Int64
    let hash: String
    let createdAt: Date
}

/// A set of 2+ files with identical content. `keeperIndex` points at the
/// item `items` is sorted to put first — the suggested copy to keep.
struct DuplicateGroup: Identifiable, Equatable {
    let id: UUID
    let hash: String
    let size: Int64
    let items: [FileRecord]
    let keeperIndex: Int

    init(id: UUID = UUID(), hash: String, size: Int64, items: [FileRecord], keeperIndex: Int = 0) {
        self.id = id
        self.hash = hash
        self.size = size
        self.items = items
        self.keeperIndex = keeperIndex
    }

    var keeper: FileRecord { items[keeperIndex] }

    /// Space reclaimed if every copy but the keeper is trashed.
    var wastedBytes: Int64 { size * Int64(items.count - 1) }
}
