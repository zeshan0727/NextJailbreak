import Foundation
import UIKit

@MainActor
final class LocalSigningController: ObservableObject {
    @Published var hasP12: Bool
    @Published var hasProvisioningProfile: Bool
    @Published var p12Password: String
    @Published var p12PasswordIsStored: Bool

    @Published var signedApps: [LocalSignedApp]
    @Published var isSigning = false
    @Published var signingProgress: Double = 0
    @Published var signingMessage: String = ""
    @Published var signingError: String?
    @Published var signingSuccess: String?

    @Published var installingID: UUID?
    @Published var installMessage: String?

    @Published var publishingID: UUID?
    @Published var publishProgress: Double = 0
    @Published var publishMessage: String?
    @Published var publishError: String?

    private let p12PasswordAccount = "p12-password"

    init() {
        hasP12 = CredentialStore.exists(.p12)
        hasProvisioningProfile = CredentialStore.exists(.provisioning)
        let storedPassword = KeychainStore.load(account: p12PasswordAccount) ?? ""
        p12Password = storedPassword
        p12PasswordIsStored = !storedPassword.isEmpty
        signedApps = LocalSignedAppsRepository.load()
    }

    var credentialsReady: Bool {
        hasP12 && hasProvisioningProfile && p12PasswordIsStored
    }

    func refreshCredentials() {
        hasP12 = CredentialStore.exists(.p12)
        hasProvisioningProfile = CredentialStore.exists(.provisioning)
        let storedPassword = KeychainStore.load(account: p12PasswordAccount) ?? ""
        p12PasswordIsStored = !storedPassword.isEmpty
        if p12Password.isEmpty { p12Password = storedPassword }
    }

    func importCredential(from url: URL, kind: CredentialStore.Kind) {
        do {
            try CredentialStore.importFile(from: url, as: kind)
            refreshCredentials()
            signingError = nil
            signingSuccess = kind == .p12
                ? "P12 certificate saved locally on this iPhone."
                : "Provisioning profile saved locally on this iPhone."
        } catch {
            signingError = "Unable to import signing credential: \(error.localizedDescription)"
        }
    }

    func saveP12Password() {
        do {
            let trimmed = p12Password
            if trimmed.isEmpty {
                KeychainStore.delete(account: p12PasswordAccount)
                p12PasswordIsStored = false
            } else {
                try KeychainStore.save(trimmed, account: p12PasswordAccount)
                p12PasswordIsStored = true
            }
            signingError = nil
            signingSuccess = p12PasswordIsStored ? "P12 password saved in Keychain." : "P12 password removed."
        } catch {
            signingError = "Could not save the P12 password: \(error.localizedDescription)"
        }
    }

    func removeCredential(_ kind: CredentialStore.Kind) {
        CredentialStore.remove(kind)
        refreshCredentials()
        signingSuccess = kind == .p12 ? "Local P12 removed." : "Local provisioning profile removed."
    }

    func refreshSignedApps() {
        signedApps = LocalSignedAppsRepository.load()
    }

    func deleteSignedApp(_ app: LocalSignedApp) {
        do {
            try LocalSignedAppsRepository.delete(app)
            refreshSignedApps()
            publishMessage = "Deleted \(app.appName) from this iPhone."
            publishError = nil
        } catch {
            publishError = "Unable to delete signed IPA: \(error.localizedDescription)"
        }
    }

    func sign(request: SignRequest) {
        guard !isSigning else { return }
        guard let ipaURL = request.ipaURL else {
            signingError = "Choose an IPA or TIPA first."
            return
        }
        let appName = request.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = request.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty, request.isValidBundleID else {
            signingError = "Enter a valid app name and bundle identifier before signing."
            return
        }
        guard hasP12 else {
            signingError = LocalSignerError.missingCertificate.localizedDescription
            return
        }
        guard hasProvisioningProfile else {
            signingError = LocalSignerError.missingProvisioningProfile.localizedDescription
            return
        }
        let password = KeychainStore.load(account: p12PasswordAccount) ?? p12Password
        guard !password.isEmpty else {
            signingError = LocalSignerError.missingPassword.localizedDescription
            return
        }

        isSigning = true
        signingProgress = 0.05
        signingMessage = "Preparing IPA locally…"
        signingError = nil
        signingSuccess = nil
        publishMessage = nil
        publishError = nil

        let p12URL = CredentialStore.url(for: .p12)
        let provisioningURL = CredentialStore.url(for: .provisioning)

        Task {
            do {
                signingProgress = 0.18
                signingMessage = "Validating certificate and provisioning profile…"
                let result = try await LocalSignerService().sign(
                    ipaURL: ipaURL,
                    requestedName: appName,
                    requestedBundleID: bundleID,
                    p12URL: p12URL,
                    provisioningURL: provisioningURL,
                    p12Password: password
                )
                signingProgress = 0.92
                signingMessage = "Saving signed IPA on this iPhone…"
                let record = try LocalSignedAppsRepository.register(result)
                refreshSignedApps()
                signingProgress = 1.0
                signingMessage = "Signed locally"
                signingSuccess = "\(record.appName) signed locally and saved in Signed Apps. Nothing was uploaded to GitHub."
            } catch {
                signingError = error.localizedDescription
                signingMessage = "Signing failed"
            }
            isSigning = false
        }
    }

    func install(_ app: LocalSignedApp, using store: SignerStore) {
        guard installingID == nil, publishingID == nil, !isSigning else { return }
        guard FileManager.default.fileExists(atPath: app.ipaURL.path) else {
            publishError = "The signed IPA is missing from this device."
            refreshSignedApps()
            return
        }
        guard store.configuration.isValid else {
            publishError = NextSignerError.invalidConfiguration.localizedDescription
            return
        }
        let token = KeychainStore.load(account: "github-token") ?? store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            publishError = "Save the GitHub PAT in Settings before using Apple OTA Install. The PAT is used only to stage the already-signed IPA temporarily; it is not published to the site."
            return
        }

        store.persistConfiguration()
        installingID = app.id
        installMessage = "Preparing Apple OTA installation…"
        publishError = nil
        publishMessage = nil

        let service = AdHocInstallService(token: token, configuration: store.configuration)
        Task {
            do {
                let result = try await service.prepareInstall(
                    ipaURL: app.ipaURL,
                    appName: app.appName,
                    bundleID: app.bundleID,
                    version: app.version,
                    build: app.build,
                    progress: { message in
                        await MainActor.run {
                            self.installMessage = message
                        }
                    }
                )

                let manifestString = result.manifestURL.absoluteString
                let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+"))
                let encoded = manifestString.addingPercentEncoding(withAllowedCharacters: allowed) ?? manifestString
                guard let installURL = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
                    throw NSError(
                        domain: "NextSigner.AdHocInstall",
                        code: 5206,
                        userInfo: [NSLocalizedDescriptionKey: "Could not create the Apple OTA installation link."]
                    )
                }

                installMessage = "Opening the iOS installation prompt…"
                let opened = await withCheckedContinuation { continuation in
                    UIApplication.shared.open(installURL, options: [:]) { success in
                        continuation.resume(returning: success)
                    }
                }
                if opened {
                    publishMessage = "Apple installation request opened for \(app.appName). This was a temporary install staging only; the app was not published to your site."
                } else {
                    publishError = "iOS did not accept the OTA install link. Confirm this iPhone is registered in the provisioning profile and try again."
                }
            } catch {
                publishError = error.localizedDescription
            }
            installingID = nil
            installMessage = nil
        }
    }

    func publish(_ app: LocalSignedApp, using store: SignerStore) {
        guard publishingID == nil, installingID == nil else { return }
        guard FileManager.default.fileExists(atPath: app.ipaURL.path) else {
            publishError = "The signed IPA is missing from this device."
            refreshSignedApps()
            return
        }
        guard store.configuration.isValid else {
            publishError = NextSignerError.invalidConfiguration.localizedDescription
            return
        }
        let token = KeychainStore.load(account: "github-token") ?? store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            publishError = "Save the GitHub PAT in Settings before publishing. Local signing does not require it."
            return
        }

        store.persistConfiguration()
        publishingID = app.id
        publishProgress = 0
        publishMessage = nil
        publishError = nil
        let service = GitHubService(token: token, configuration: store.configuration)

        Task {
            do {
                _ = try await service.uploadAndDispatch(
                    ipaURL: app.ipaURL,
                    appName: app.appName,
                    bundleID: app.bundleID,
                    customIconURL: nil,
                    tweakURLs: [],
                    signingEnabled: false,
                    duplicateSigning: false,
                    injectExtensions: false,
                    weakInjection: false,
                    progress: { value in
                        await MainActor.run { self.publishProgress = value }
                    }
                )
                publishProgress = 1
                publishMessage = "\(app.appName) published successfully. GitHub was used only for site/R2 publishing; the IPA was not re-signed."
            } catch {
                publishError = error.localizedDescription
            }
            publishingID = nil
        }
    }
}
