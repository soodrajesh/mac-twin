import AppKit
import SwiftUI

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

/// The app's Text Size setting, in points-per-style plus a per-view
/// `.appFont(_:weight:)` modifier — deliberately *not* SwiftUI's
/// `.dynamicTypeSize`/`Font.TextStyle`, because Dynamic Type is an iOS/
/// iPadOS/tvOS/watchOS mechanism with no effect on macOS. This reimplements
/// the same idea with a real effect: a scale factor read from the
/// environment, applied to a fixed base point size per semantic role,
/// computed fresh at render time so Settings changes apply live. Mirrors
/// mac-cleanup's `Support.swift` — see that file's comment for the
/// verification note this pattern is based on.
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// License status: whether the user has a valid MacTwin Pro license.
/// Free tier (full scan + review + manual trash — the core safety-first
/// loop) has no expiry and no trial; Pro gates scheduled scans, report
/// export, smart auto-select, and unlimited custom-folder scan scope. See
/// `MacTwinLicenseCheck.swift`.
private struct IsProLicensedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isProLicensed: Bool {
        get { self[IsProLicensedKey.self] }
        set { self[IsProLicensedKey.self] = newValue }
    }
}

/// One semantic role → one base point size, matching macOS's own
/// approximate `NSFont.preferredFont(forTextStyle:)` values. Drop-in
/// replacement for `.font(.caption)` etc. — every body-text call site
/// should route through `.appFont` instead so Settings' Text Size
/// preference has a real effect.
enum AppFontStyle {
    case largeTitle, title, title2, title3
    case headline, body, callout, subheadline, footnote, caption, caption2

    var basePointSize: CGFloat {
        switch self {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .body:        return 13
        case .callout:     return 12
        case .subheadline: return 11
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 10
        }
    }

    /// SwiftUI's real `.headline` renders semibold, not regular — every
    /// other style here defaults to regular. `appFont`'s explicit `weight:`
    /// parameter still overrides this either way.
    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: AppFontStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(.system(size: style.basePointSize * scale, weight: weight ?? style.defaultWeight))
    }
}

extension View {
    /// Replaces `.font(.caption)`, `.font(.headline)`, etc. throughout the
    /// app — every call site needs this instead of a raw `Font.TextStyle`
    /// for Settings' Text Size to have any real effect. `weight` is `nil`
    /// by default so styles with their own natural weight (just
    /// `.headline`, semibold) keep it unless a caller explicitly overrides.
    func appFont(_ style: AppFontStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weight: weight))
    }
}

extension URL {
    /// The full path with the home directory collapsed to `~`, so every
    /// item row can show exactly where a file lives without the noise of a
    /// long absolute path.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
