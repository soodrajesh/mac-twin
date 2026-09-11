import SwiftUI

@main
struct MacTwinApp: App {
    @StateObject private var model = DupeModel()

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium
    @AppStorage(PolarConfig.storedKeyDefaultsKey) private var storedLicenseKey = ""
    @AppStorage("scheduledScansEnabled") private var scheduledScansEnabled = false
    @AppStorage("scheduledScanIntervalHours") private var scheduledScanIntervalHours = ScheduledScanInterval.daily.rawValue

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
                .onChange(of: isProLicensed) { licensed in
                    model.configureScheduledScans(
                        enabled: licensed && scheduledScansEnabled,
                        intervalHours: scheduledScanIntervalHours)
                }
                .onChange(of: scheduledScansEnabled) { enabled in
                    model.configureScheduledScans(
                        enabled: isProLicensed && enabled,
                        intervalHours: scheduledScanIntervalHours)
                }
                .onChange(of: scheduledScanIntervalHours) { hours in
                    model.configureScheduledScans(
                        enabled: isProLicensed && scheduledScansEnabled,
                        intervalHours: hours)
                }
                .onChange(of: model.hasScanned) { scanned in
                    // A manual scan just finished — re-arm the scheduler
                    // so a future background run uses the folders/filter
                    // that were actually just used.
                    guard scanned else { return }
                    model.configureScheduledScans(
                        enabled: isProLicensed && scheduledScansEnabled,
                        intervalHours: scheduledScanIntervalHours)
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

        do {
            let license = try await checker.verify(licenseKey: storedLicenseKey)
            isProLicensed = license.isValid
        } catch {
            isProLicensed = false
        }
    }
}
