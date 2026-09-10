import Foundation

/// Pro-only auto-select strategies. `.keepOldest` matches the free-tier
/// default (`DuplicateGrouping`'s own keeper choice) and is offered here
/// too for symmetry; the other two are the actual Pro-gated behavior.
enum AutoSelectStrategy: String, CaseIterable, Identifiable {
    case keepOldest = "Keep Oldest"
    case keepNewest = "Keep Newest"
    case keepShortestPath = "Keep Shortest Path"

    var id: String { rawValue }
}

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
    private var scheduledActivity: NSBackgroundActivityScheduler?

    /// Last roots/extensions a scan actually ran with — what a Pro
    /// scheduled scan re-runs against, since there's no separate
    /// "scheduled folders" picker to keep in sync with StartView's.
    private var lastScanRoots: [URL] = []
    private var lastScanExtensions: Set<String>?

    var totalWastedBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    var selectedBytes: Int64 {
        groups.reduce(0) { total, group in
            total + group.items.filter { selectedForTrash.contains($0.url) }.reduce(0) { $0 + $1.size }
        }
    }

    /// Groups where the current selection would trash *every* copy,
    /// including the suggested keeper — i.e. zero survivors. Surfaced as a
    /// hard-stop warning in `ConfirmDeletionSheet` before the destructive
    /// action is allowed to proceed, since selection is a flat `Set<URL>`
    /// with no per-group "keep at least one" bookkeeping elsewhere.
    var groupsWithNoSurvivors: [DuplicateGroup] {
        groups.filter { group in
            group.items.allSatisfy { selectedForTrash.contains($0.url) }
        }
    }

    /// True whenever the user has completed results on screen to review —
    /// used to defer a Pro scheduled scan rather than silently discarding
    /// an in-progress manual review (see `configureScheduledScans`).
    var isReviewingResults: Bool {
        hasScanned && !groups.isEmpty
    }

    func startScan(roots: [URL], extensions: Set<String>? = nil) {
        scanTask?.cancel()
        lastScanRoots = roots
        lastScanExtensions = extensions
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
            var trashed: [URL] = []
            TrashService.moveToTrash(urls, isCancelled: { false }) { i, outcome in
                if outcome.success {
                    trashed.append(outcome.url)
                } else if let error = outcome.error {
                    failures.append("\(outcome.url.lastPathComponent): \(error)")
                }
                Task { @MainActor in self.deletionProgress = (i + 1, urls.count) }
            }
            let failureMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
            let succeeded = trashed
            await MainActor.run {
                self.removeTrashed(succeeded)
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

    // MARK: - Pro: smart auto-select

    /// Recomputes `selectedForTrash` under an alternate keeper strategy —
    /// does not touch `group.keeperIndex` (the free-tier "Suggested keep"
    /// badge stays put; this only changes which copies end up checked).
    func applyAutoSelect(_ strategy: AutoSelectStrategy) {
        var selected: Set<URL> = []
        for group in groups {
            let keep = keeperIndex(for: group.items, strategy: strategy)
            for (i, item) in group.items.enumerated() where i != keep {
                selected.insert(item.url)
            }
        }
        selectedForTrash = selected
    }

    private func keeperIndex(for items: [FileRecord], strategy: AutoSelectStrategy) -> Int {
        switch strategy {
        case .keepOldest:
            return items.enumerated().min { a, b in
                a.element.createdAt != b.element.createdAt
                    ? a.element.createdAt < b.element.createdAt
                    : a.element.url.path.count < b.element.url.path.count
            }?.offset ?? 0
        case .keepNewest:
            return items.enumerated().max { a, b in
                a.element.createdAt != b.element.createdAt
                    ? a.element.createdAt < b.element.createdAt
                    : a.element.url.path.count > b.element.url.path.count
            }?.offset ?? 0
        case .keepShortestPath:
            return items.enumerated().min { $0.element.url.path.count < $1.element.url.path.count }?.offset ?? 0
        }
    }

    // MARK: - Pro: export report

    /// Writes a CSV summary of every duplicate set — one row per file,
    /// noting the suggested keeper and current Trash selection — so a Pro
    /// user can archive or share a scan's findings outside the app.
    func exportReport(to url: URL) throws {
        var lines = ["Set,File,Folder,Size (bytes),Created,Suggested Keep,Selected For Trash"]
        let formatter = ISO8601DateFormatter()
        for (setIndex, group) in groups.enumerated() {
            for (i, item) in group.items.enumerated() {
                let fields = [
                    String(setIndex + 1),
                    item.url.lastPathComponent,
                    item.url.deletingLastPathComponent().path,
                    String(item.size),
                    formatter.string(from: item.createdAt),
                    i == group.keeperIndex ? "Yes" : "No",
                    selectedForTrash.contains(item.url) ? "Yes" : "No",
                ]
                lines.append(fields.map(csvField).joined(separator: ","))
            }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Pro: scheduled background scans

    /// Starts, reconfigures, or stops a repeating background scan of the
    /// last folders/filter a manual scan actually used. Called whenever
    /// license status or the Settings toggle/interval changes — always
    /// safe to call with `enabled: false` even if nothing was scheduled.
    func configureScheduledScans(enabled: Bool, intervalHours: Int) {
        scheduledActivity?.invalidate()
        scheduledActivity = nil
        guard enabled, !lastScanRoots.isEmpty else { return }

        let activity = NSBackgroundActivityScheduler(identifier: "com.rajeshsood.mactwin.scheduledscan")
        activity.repeats = true
        activity.interval = TimeInterval(max(1, intervalHours) * 3600)
        activity.tolerance = activity.interval * 0.1
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            guard let self else { completion(.finished); return }
            Task { @MainActor in
                // Don't clobber an active review session: a scan already
                // running, or unreviewed results still on screen (the user
                // may have hand-adjusted selections that `startScan` would
                // silently discard). Defer rather than run — the next
                // scheduled tick, or the user's next manual scan, will
                // catch up once they've moved past ResultsView.
                guard !self.isScanning, !self.isReviewingResults else { completion(.finished); return }
                self.startScan(roots: self.lastScanRoots, extensions: self.lastScanExtensions)
                completion(.finished)
            }
        }
        scheduledActivity = activity
    }
}
