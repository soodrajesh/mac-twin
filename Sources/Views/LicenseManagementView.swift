import SwiftUI

/// Template: MacGroom's `LicenseManagementView.swift`. Same visual card
/// pattern and verification flow, scoped to MacTwin's own license key
/// and `LicenseChecker` (`MacTwinLicenseCheck.swift`).
struct LicenseManagementView: View {
    @AppStorage(PolarConfig.storedKeyDefaultsKey) private var storedLicenseKey = ""

    // Settings is its own Scene/window — it doesn't inherit the main
    // WindowGroup's `.environment(\.isProLicensed, ...)`, so this view
    // verifies independently rather than reading that environment value.
    private let checker = LicenseChecker()

    @State private var isLicenseActive = false
    @State private var showLicenseEntry = false
    @State private var verificationMessage = ""
    @State private var verificationError = false
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.appAccent)
                } else {
                    Image(systemName: isLicenseActive ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isLicenseActive ? .appAccent : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacTwin Pro")
                        .appFont(.headline)
                    Text(isVerifying ? "Verifying…" : (isLicenseActive ? "License Active" : "Free Version"))
                        .appFont(.caption, weight: .regular)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 1))

            if !verificationMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: verificationError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundColor(verificationError ? .red : .green)
                    Text(verificationMessage)
                        .appFont(.caption)
                }
                .padding(10)
                .background(verificationError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 8) {
                Button(action: { showLicenseEntry = true }) {
                    Text(storedLicenseKey.isEmpty ? "Enter License Key" : "Update License")
                        .appFont(.body)
                }
                .buttonStyle(.bordered)

                if !storedLicenseKey.isEmpty {
                    Button(action: clearLicense) {
                        Image(systemName: "xmark.circle")
                            .appFont(.body)
                    }
                    .buttonStyle(.bordered)
                    .help("Remove stored license key")
                }

                if storedLicenseKey.isEmpty {
                    Button("Buy MacTwin Pro") {
                        NSWorkspace.shared.open(PolarConfig.purchaseURL)
                    }
                    .buttonStyle(.link)
                    .appFont(.body)
                }
            }
        }
        .sheet(isPresented: $showLicenseEntry) {
            LicenseEntrySheet(
                isPresented: $showLicenseEntry,
                onLicenseEntered: handleLicenseEntry
            )
        }
        .task(id: storedLicenseKey) {
            guard !storedLicenseKey.isEmpty else {
                isLicenseActive = false
                return
            }
            await verify(storedLicenseKey)
        }
    }

    private func handleLicenseEntry(_ key: String) {
        storedLicenseKey = key
        showLicenseEntry = false
        // `.task(id: storedLicenseKey)` above re-runs verification
        // automatically now that the key changed.
    }

    private func verify(_ key: String) async {
        if OwnerAccess.isOwnerKey(key) {
            isLicenseActive = true
            verificationMessage = "MacTwin Pro unlocked (owner build)."
            verificationError = false
            return
        }

        isVerifying = true
        verificationMessage = ""
        defer { isVerifying = false }

        do {
            let license = try await checker.verify(licenseKey: key)
            isLicenseActive = license.isValid
            verificationMessage = "License verified — MacTwin Pro unlocked."
            verificationError = false
        } catch {
            isLicenseActive = false
            verificationMessage = (error as? LicenseCheckError)?.errorDescription ?? "License verification failed."
            verificationError = true
        }
    }

    private func clearLicense() {
        checker.clearCache(storedLicenseKey)
        storedLicenseKey = ""
        isLicenseActive = false
        verificationMessage = "License key removed"
        verificationError = false
    }
}

struct LicenseEntrySheet: View {
    @Binding var isPresented: Bool
    var onLicenseEntered: (String) -> Void

    @State private var licenseKey = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enter License Key")
                    .appFont(.title3)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your license key from the email you received after purchase:")
                    .appFont(.body)
                    .foregroundColor(.secondary)

                TextEditor(text: $licenseKey)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .border(Color.gray.opacity(0.3), width: 1)
            }

            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .appFont(.caption)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save License") {
                    saveLicense()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 450, height: 320)
    }

    private func saveLicense() {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            errorMessage = "License key cannot be empty"
            return
        }

        let validCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard trimmedKey.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            errorMessage = "License key contains invalid characters"
            return
        }

        onLicenseEntered(trimmedKey)
        isPresented = false
    }
}
