import Foundation

/// User-maintained list of folders MacTwin should never scan — the fix for
/// "it keeps finding duplicates inside a folder I deliberately keep messy"
/// (a Downloads subfolder of intentional redundant copies, a project's
/// `node_modules`/build output, etc.). Persisted as absolute path strings in
/// `UserDefaults`, matching the app's `@AppStorage`-for-simple-settings
/// convention elsewhere (`SettingsView`). Ported from MacGroom's
/// `ExclusionStore.swift`, same pattern.
///
/// Applied in `DuplicateScanner.enumerate(_:)` during the filesystem walk
/// itself — an excluded directory has its descendants skipped outright
/// (not just filtered out after the fact), so a large excluded subtree
/// costs nothing beyond the single `stat` that identifies it.
enum ExclusionStore {
    private static let key = "excludedPaths.v1"

    static var paths: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func add(_ url: URL) {
        var current = paths
        let path = url.path
        guard !current.contains(path) else { return }
        current.append(path)
        paths = current
    }

    static func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    /// True if `url` is itself an excluded path, or is nested under one —
    /// excluding `~/Downloads/archive` should also skip everything inside
    /// it, not just that exact path.
    static func isExcluded(_ url: URL) -> Bool {
        let path = url.path
        return paths.contains { excluded in
            path == excluded || path.hasPrefix(excluded.hasSuffix("/") ? excluded : excluded + "/")
        }
    }
}
