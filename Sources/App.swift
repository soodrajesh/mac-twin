import SwiftUI

@main
struct MacTwinApp: App {
    @StateObject private var model = DupeModel()

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium
    @AppStorage(PolarConfig.storedKeyDefaultsKey) private var storedLicenseKey = ""

    @State private var licenseChecker: LicenseChecker?
    @State private var isProLicensed = false

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .environment(\.textScale, textSize.scaleFactor)
                .environment(\.isProLicensed, isProLicensed)
                .frame(minWidth: 640, minHeight: 560)
                .preferredColorScheme(appearanceMode.colorScheme)
                // `.task`, not `.onAppear` — `onAppear` can refire when a
                // system permission dialog interrupts and restores the
                // window. `.task(id:)` also re-runs whenever the stored
                // key changes (entered, updated, or cleared).
                .task(id: storedLicenseKey) {
                    licenseChecker = LicenseChecker()
                    await verifyLicense()
                }
                .task {
                    model.checkForUpdates()
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.isProLicensed, isProLicensed)
        }
    }

    private func verifyLicense() async {
        guard let checker = licenseChecker else { return }
        guard !storedLicenseKey.isEmpty else {
            // Don't skip this — clearing the key must actually revoke Pro
            // access immediately, not just stop future verification.
            isProLicensed = false
            return
        }
        if OwnerAccess.isOwnerKey(storedLicenseKey) {
            isProLicensed = true
            return
        }

        do {
            let license = try await checker.verify(licenseKey: storedLicenseKey)
            isProLicensed = license.isValid
        } catch {
            isProLicensed = false
        }
    }
}
