import Foundation

var failures = 0

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        failures += 1
    }
}

func makeRecord(_ path: String, size: Int64, hash: String, daysAgo: Int = 0) -> FileRecord {
    let created = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    return FileRecord(url: URL(fileURLWithPath: path), size: size, hash: hash, createdAt: created)
}

// MARK: - Unique sizes never group, even with colliding hashes

do {
    let records = [
        makeRecord("/a", size: 100, hash: "x"),
        makeRecord("/b", size: 200, hash: "x"),
    ]
    let groups = DuplicateGrouping.group(records)
    expect(groups.isEmpty, "different sizes must never be grouped, regardless of hash")
}

// MARK: - Same size + same hash groups; same size + different hash does not

do {
    let records = [
        makeRecord("/a", size: 100, hash: "x"),
        makeRecord("/b", size: 100, hash: "x"),
        makeRecord("/c", size: 100, hash: "y"),
    ]
    let groups = DuplicateGrouping.group(records)
    expect(groups.count == 1, "expected exactly one duplicate group, got \(groups.count)")
    expect(groups.first?.items.count == 2, "duplicate group should contain the two matching files only")
}

// MARK: - Singletons (no size or hash match) are dropped entirely

do {
    let records = [makeRecord("/a", size: 100, hash: "x")]
    expect(DuplicateGrouping.group(records).isEmpty, "a lone file must never form a group")
}

// MARK: - Keeper is the oldest by creation date

do {
    let records = [
        makeRecord("/newer", size: 100, hash: "x", daysAgo: 1),
        makeRecord("/older", size: 100, hash: "x", daysAgo: 10),
    ]
    let group = DuplicateGrouping.group(records).first!
    expect(group.keeper.url.path == "/older", "keeper should be the oldest file, got \(group.keeper.url.path)")
}

// MARK: - Ties on creation date broken by shorter path

do {
    let sameDate = Date()
    let records = [
        FileRecord(url: URL(fileURLWithPath: "/very/deeply/nested/copy.txt"), size: 100, hash: "x", createdAt: sameDate),
        FileRecord(url: URL(fileURLWithPath: "/short.txt"), size: 100, hash: "x", createdAt: sameDate),
    ]
    let group = DuplicateGrouping.group(records).first!
    expect(group.keeper.url.path == "/short.txt", "keeper tie-break should favor the shorter path, got \(group.keeper.url.path)")
}

// MARK: - Groups sorted by wasted space, largest first

do {
    let records = [
        makeRecord("/small1", size: 10, hash: "small"),
        makeRecord("/small2", size: 10, hash: "small"),
        makeRecord("/big1", size: 1000, hash: "big"),
        makeRecord("/big2", size: 1000, hash: "big"),
    ]
    let groups = DuplicateGrouping.group(records)
    expect(groups.first?.hash == "big", "groups should be sorted with the most-wasted-space group first")
}

// MARK: - FileTypeFilter

do {
    expect(FileTypeFilter.matches(URL(fileURLWithPath: "/a.jpg"), extensions: nil),
           "nil extensions must match everything")
    expect(FileTypeFilter.matches(URL(fileURLWithPath: "/a.jpg"), extensions: []),
           "empty extensions set must match everything")
    expect(FileTypeFilter.matches(URL(fileURLWithPath: "/a.JPG"), extensions: ["jpg"]),
           "matching must be case-insensitive on the file's extension")
    expect(!FileTypeFilter.matches(URL(fileURLWithPath: "/a.png"), extensions: ["jpg"]),
           "a non-matching extension must be excluded")
    expect(FileTypeFilter.matches(URL(fileURLWithPath: "/a.pdf"), extensions: FileCategory.documents.extensions),
           "pdf must be covered by the Documents category")
}

if failures == 0 {
    print("All tests passed.")
} else {
    print("\(failures) test(s) failed.")
    exit(1)
}
