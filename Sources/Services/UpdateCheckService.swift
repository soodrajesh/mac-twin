import Foundation

/// The manifest MacTwin polls to learn a newer version exists, served from
/// gogenops.com/mac-apps/mactwin/updates.json through `/api/update-check`
/// (server-side already live — see MacGroom's `UpdateCheckService.swift`,
/// which this mirrors, for why the poll goes through that endpoint instead
/// of fetching the static file directly).
struct UpdateManifest: Codable, Equatable {
    let version: String
    let notes: String?
    let url: String
}

/// Lightweight, safe update *checking* — deliberately not silent
/// auto-update. Compares the hosted manifest's version against this
/// build's own `CFBundleShortVersionString` and, if newer, hands back the
/// manifest for the UI to show a "vX is available" prompt linking out to
/// wherever `url` points. Doesn't download or replace the running app
/// bundle itself: that needs a signature-verification story (otherwise
/// anyone who can spoof the manifest response — a compromised host, a
/// MITM on a plain HTTP mirror, a DNS-level attacker — could point
/// MacTwin at an arbitrary binary) this app doesn't have yet. Silent
/// self-replacement is tracked as a deliberate follow-up, not something
/// to bolt on here.
enum UpdateCheckService {
    static func checkForUpdate() async -> UpdateManifest? {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        var components = URLComponents(string: "https://gogenops.com/api/update-check")!
        components.queryItems = [
            URLQueryItem(name: "app", value: "mactwin"),
            URLQueryItem(name: "v", value: currentVersion),
            URLQueryItem(name: "os", value: macOSVersionString()),
        ]

        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data) else { return nil }

        return isNewer(manifest.version, than: currentVersion) ? manifest : nil
    }

    private static func macOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Component-wise numeric comparison ("1.10" > "1.9"), not a string
    /// compare (which would get that backwards) — pads the shorter side
    /// with zeros so "1.2" vs "1.2.1" compares correctly too.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
