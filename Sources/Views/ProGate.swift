import SwiftUI

/// Small reusable "this needs MacTwin Pro" upsell pieces — gated
/// features show these instead of silently disabling, per the design
/// system's Pro-gating pattern. Tapping opens Settings (⌘,) where License
/// lives, rather than just disabling the control with no explanation.
struct UnlockProButton: View {
    var label: String = "Unlock Pro"

    var body: some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            Label(label, systemImage: "lock.fill")
                .appFont(.caption, weight: .semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.small)
    }
}

/// Inline "PRO" pill next to a feature's label.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .appFont(.caption2, weight: .bold)
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }
}
