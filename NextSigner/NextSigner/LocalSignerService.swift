import Foundation
import Security
import ZIPFoundation
import Zsign

struct SignedAppResult: Equatable {
    let ipaURL: URL
    let appName: String
    let bundleID: String
    let version: String
    let build: String
    let minimumOS: String
}

enum LocalSignerError: LocalizedError {
    case missingCertificate
    case missingProvisioningProfile
    case missingPassword
    case invalidIPA
    case appBundleMissing
    case infoPlistMissing
    case invalidCertificateOrPassword(OSStatus)
    case certificateMissingFromP12
    case invalidProvisioningProfile
    case expiredProvisioningProfile(String)
    case certificateNotAllowedByProfile
    case bundleIdentifierNotAllowed(String, String)
    case nestedBundleNotAllowed(String, String)
    case signingFailed
    case signedProfileMissing
    case metadataValidationFailed
    case packagingFailed
    case invalidExplicitEntitlements(String)
    case signedEntitlementsMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingCertificate:
            return "Import a .p12 signing certificate in Settings first."
        case .missingProvisioningProfile:
            return "Import a .mobileprovision profile in Settings first."
        case .missingPassword:
            return "Enter and save the P12 password in Settings first."
        case .invalidIPA:
            return "The selected file is not a valid IPA/TIPA archive with a Payload app."
        case .appBundleMissing:
            return "No application bundle was found inside Payload."
        case .infoPlistMissing:
            return "The app Info.plist could not be read."
        case let .invalidCertificateOrPassword(status):
            return "The P12 certificate could not be opened (Security error \(status)). Check the P12 password and import the certificate again."
        case .certificateMissingFromP12:
            return "The imported P12 does not contain a usable signing identity and certificate."
        case .invalidProvisioningProfile:
            return "The mobileprovision file could not be decoded or is missing its signing entitlements."
        case let .expiredProvisioningProfile(date):
            return "The provisioning profile expired on \(date). Create/import a current profile before signing."
        case .certificateNotAllowedByProfile:
            return "The P12 certificate is not one of the developer certificates authorized by this provisioning profile. Import a matching P12/profile pair."
        case let .bundleIdentifierNotAllowed(bundleID, pattern):
            return "The provisioning profile allows \(pattern), but the requested bundle identifier is \(bundleID). Use a matching identifier or profile."
        case let .nestedBundleNotAllowed(bundleID, pattern):
            return "A nested app/extension uses \(bundleID), which is not covered by the provisioning profile \(pattern). Apps with special extensions may require their own profiles."
        case .signingFailed:
            return "Zsign could not sign the app. The P12/profile preflight passed, so this IPA likely contains an unsupported executable, extension, or entitlement combination."
        case .signedProfileMissing:
            return "Zsign completed, but embedded.mobileprovision was not written into the signed app."
        case .metadataValidationFailed:
            return "Signing completed, but the final app metadata did not match the requested bundle identifier."
        case .packagingFailed:
            return "The app was signed but the final IPA could not be packaged correctly."
        case .invalidExplicitEntitlements(let reason):
            return "Cannot enable requested entitlements: \(reason)"
        case .signedEntitlementsMismatch(let key):
            return "The final IPA signature does not contain the requested entitlement: \(key). No IPA was exported."
        }
    }
}

private struct ProvisioningProfileInfo {
    let name: String
    let expirationDate: Date
    let applicationIdentifierPattern: String
    let developerCertificates: [Data]
    let teamID: String
    let permittedEntitlements: [String: Any]

    func allows(bundleID: String) -> Bool {
        let pattern = applicationIdentifierPattern
        if pattern == "*" { return true }
        if pattern.hasSuffix("*") {
            return bundleID.hasPrefix(String(pattern.dropLast()))
        }
        return bundleID == pattern
    }
}

struct LocalSignerService {
    func sign(
        ipaURL: URL,
        requestedName: String,
        requestedBundleID: String,
        p12URL: URL,
        provisioningURL: URL,
        p12Password: String,
        customEntitlementsURL: URL?,
        iCloudDocuments: Bool,
        iCloudContainer: String
    ) async throws -> SignedAppResult {
        try await Task.detached(priority: .userInitiated) {
            try signSynchronously(
                ipaURL: ipaURL,
                requestedName: requestedName,
                requestedBundleID: requestedBundleID,
                p12URL: p12URL,
                provisioningURL: provisioningURL,
                p12Password: p12Password,
                customEntitlementsURL: customEntitlementsURL,
                iCloudDocuments: iCloudDocuments,
                iCloudContainer: iCloudContainer
            )
        }.value
    }

    private func signSynchronously(
        ipaURL: URL,
        requestedName: String,
        requestedBundleID: String,
        p12URL: URL,
        provisioningURL: URL,
        p12Password: String,
        customEntitlementsURL: URL?,
        iCloudDocuments: Bool,
        iCloudContainer: String
    ) throws -> SignedAppResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: p12URL.path) else { throw LocalSignerError.missingCertificate }
        guard fm.fileExists(atPath: provisioningURL.path) else { throw LocalSignerError.missingProvisioningProfile }
        guard !p12Password.isEmpty else { throw LocalSignerError.missingPassword }

        let cleanName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundleID = requestedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate the P12/profile pair up front so configuration problems are
        // reported before extraction/signing instead of as misleading signature errors.
        let p12Certificate = try certificateDER(fromP12: p12URL, password: p12Password)
        let profile = try provisioningProfileInfo(from: provisioningURL)

        if profile.expirationDate <= Date() {
            throw LocalSignerError.expiredProvisioningProfile(Self.dateFormatter.string(from: profile.expirationDate))
        }
        guard profile.developerCertificates.contains(p12Certificate) else {
            throw LocalSignerError.certificateNotAllowedByProfile
        }
        guard profile.allows(bundleID: cleanBundleID) else {
            throw LocalSignerError.bundleIdentifierNotAllowed(cleanBundleID, profile.applicationIdentifierPattern)
        }

        let workRoot = fm.temporaryDirectory.appendingPathComponent("NextSigner-\(UUID().uuidString)", isDirectory: true)
        let unpacked = workRoot.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workRoot) }

        let signingEntitlements = try makeExplicitEntitlements(
            profile: profile,
            bundleID: cleanBundleID,
            iCloudDocuments: iCloudDocuments,
            iCloudContainer: iCloudContainer,
            customURL: customEntitlementsURL,
            workRoot: workRoot
        )

        do {
            try fm.unzipItem(at: ipaURL, to: unpacked)
        } catch {
            throw LocalSignerError.invalidIPA
        }

        let appURL = try findMainApp(in: unpacked)
        let originalBundleID = try updateMainAppMetadata(appURL: appURL, appName: cleanName, bundleID: cleanBundleID)
        let nestedBundleIDs = try updateNestedBundleIdentifiers(
            in: appURL,
            originalMainBundleID: originalBundleID,
            newMainBundleID: cleanBundleID
        )

        for nestedID in nestedBundleIDs where !profile.allows(bundleID: nestedID) {
            throw LocalSignerError.nestedBundleNotAllowed(nestedID, profile.applicationIdentifierPattern)
        }

        // Upstream zsign supports signing an unsigned app/Mach-O and can allocate
        // code-signature space itself. Its return value is the signing authority.
        // Do not second-guess a successful sign with checkSigned(), CodeResources,
        // or a custom LC_CODE_SIGNATURE parser; those caused false failures.
        var completionResult: Bool?
        let signedOK = Zsign.sign(
            appPath: appURL.path,
            provisionPath: provisioningURL.path,
            p12Path: p12URL.path,
            p12Password: p12Password,
            entitlementsPath: signingEntitlements?.path ?? "",
            customIdentifier: cleanBundleID,
            customName: cleanName,
            customVersion: "",
            adhoc: false,
            removeProvision: false,
            completion: { completionResult = $0 }
        )
        guard signedOK, completionResult != false else { throw LocalSignerError.signingFailed }
        if let signingEntitlements {
            try verifySignedEntitlements(appURL: appURL, expectedURL: signingEntitlements)
        }

        // Post-sign checks intentionally validate package state only. Zsign already
        // performed the Mach-O signing operation.
        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let plist = try readPlist(plistURL) else { throw LocalSignerError.infoPlistMissing }

        let finalName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? cleanName
        let finalBundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (plist["CFBundleVersion"] as? String) ?? "1"
        let minimumOS = (plist["MinimumOSVersion"] as? String) ?? "iOS"

        guard finalBundleID == cleanBundleID else {
            throw LocalSignerError.metadataValidationFailed
        }

        let embeddedProfile = appURL.appendingPathComponent("embedded.mobileprovision")
        guard fm.fileExists(atPath: embeddedProfile.path), fileHasContent(embeddedProfile) else {
            throw LocalSignerError.signedProfileMissing
        }

        let signedDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSigner Signed", isDirectory: true)
        try fm.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let outputURL = signedDirectory.appendingPathComponent(
            "\(safeFilename(finalName))-\(safeFilename(version))-signed-\(Int(Date().timeIntervalSince1970)).ipa"
        )
        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }

        do {
            try fm.zipItem(at: unpacked, to: outputURL, shouldKeepParent: false, compressionMethod: .deflate)
        } catch {
            throw LocalSignerError.packagingFailed
        }

        guard fm.fileExists(atPath: outputURL.path), fileHasContent(outputURL), isZIPArchive(outputURL) else {
            throw LocalSignerError.packagingFailed
        }

        return SignedAppResult(
            ipaURL: outputURL,
            appName: finalName,
            bundleID: finalBundleID,
            version: version,
            build: build,
            minimumOS: minimumOS
        )
    }

    // MARK: - Credential preflight

    private func certificateDER(fromP12 url: URL, password: String) throws -> Data {
        let p12Data: Data
        do {
            p12Data = try Data(contentsOf: url)
        } catch {
            throw LocalSignerError.certificateMissingFromP12
        }

        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var imported: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options, &imported)
        guard status == errSecSuccess else {
            throw LocalSignerError.invalidCertificateOrPassword(status)
        }
        guard let items = imported as? [[String: Any]],
              let first = items.first,
              let identityValue = first[kSecImportItemIdentity as String] else {
            throw LocalSignerError.certificateMissingFromP12
        }

        let cfIdentity = identityValue as CFTypeRef
        guard CFGetTypeID(cfIdentity) == SecIdentityGetTypeID() else {
            throw LocalSignerError.certificateMissingFromP12
        }
        let identity = unsafeBitCast(cfIdentity, to: SecIdentity.self)

        var certificate: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard certificateStatus == errSecSuccess, let certificate else {
            throw LocalSignerError.certificateMissingFromP12
        }
        return SecCertificateCopyData(certificate) as Data
    }

    private func provisioningProfileInfo(from url: URL) throws -> ProvisioningProfileInfo {
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            throw LocalSignerError.invalidProvisioningProfile
        }

        let xmlStart = Data("<?xml".utf8)
        let plistEnd = Data("</plist>".utf8)
        guard let start = raw.range(of: xmlStart),
              let end = raw.range(of: plistEnd, options: [], in: start.lowerBound..<raw.endIndex) else {
            throw LocalSignerError.invalidProvisioningProfile
        }

        let plistData = raw.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let plist = object as? [String: Any],
              let expiration = plist["ExpirationDate"] as? Date,
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            throw LocalSignerError.invalidProvisioningProfile
        }

        let teamIDs = plist["TeamIdentifier"] as? [String] ?? []
        let teamID = (entitlements["com.apple.developer.team-identifier"] as? String) ?? teamIDs.first ?? ""
        let fullApplicationIdentifier = (entitlements["application-identifier"] as? String)
            ?? (entitlements["com.apple.application-identifier"] as? String)
            ?? ""
        guard !fullApplicationIdentifier.isEmpty else {
            throw LocalSignerError.invalidProvisioningProfile
        }

        let pattern: String
        if !teamID.isEmpty, fullApplicationIdentifier.hasPrefix(teamID + ".") {
            pattern = String(fullApplicationIdentifier.dropFirst(teamID.count + 1))
        } else if let dot = fullApplicationIdentifier.firstIndex(of: ".") {
            pattern = String(fullApplicationIdentifier[fullApplicationIdentifier.index(after: dot)...])
        } else {
            pattern = fullApplicationIdentifier
        }

        let certificates = (plist["DeveloperCertificates"] as? [Any])?.compactMap { $0 as? Data } ?? []
        guard !certificates.isEmpty else { throw LocalSignerError.invalidProvisioningProfile }

        return ProvisioningProfileInfo(
            name: (plist["Name"] as? String) ?? "Provisioning Profile",
            expirationDate: expiration,
            applicationIdentifierPattern: pattern,
            developerCertificates: certificates,
            teamID: teamID,
            permittedEntitlements: entitlements
        )
    }

    // MARK: - Explicit capabilities

    /// Zsign's entitlementsPath overrides the final Mach-O entitlement blob;
    /// derive the mandatory identity keys from the exact selected provisioning
    /// profile, then add only profile-authorized explicit capability requests.
    private func makeExplicitEntitlements(
        profile: ProvisioningProfileInfo,
        bundleID: String,
        iCloudDocuments: Bool,
        iCloudContainer: String,
        customURL: URL?,
        workRoot: URL
    ) throws -> URL? {
        guard iCloudDocuments || customURL != nil else { return nil }
        guard !iCloudDocuments || customURL == nil else {
            throw LocalSignerError.invalidExplicitEntitlements("Choose either the iCloud preset or a custom .entitlements file.")
        }
        guard !profile.teamID.isEmpty, !profile.applicationIdentifierPattern.contains("*"),
              profile.applicationIdentifierPattern == bundleID else {
            throw LocalSignerError.invalidExplicitEntitlements("Import an explicit App ID Ad Hoc profile matching " + bundleID + " (no wildcard).")
        }

        let applicationIdentifier = profile.teamID + "." + bundleID
        var entitlement: [String: Any] = [
            "application-identifier": applicationIdentifier,
            "com.apple.developer.team-identifier": profile.teamID,
            "get-task-allow": false
        ]
        if let groups = profile.permittedEntitlements["keychain-access-groups"] as? [String],
           groups.contains(where: { self.isAllowed(applicationIdentifier, by: $0) }) {
            entitlement["keychain-access-groups"] = [applicationIdentifier]
        }
        if iCloudDocuments {
            let container = iCloudContainer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard container.hasPrefix("iCloud."), !container.contains(" "),
                  !container.contains("*") else {
                throw LocalSignerError.invalidExplicitEntitlements("Enter the exact iCloud container, e.g. iCloud.com.nextsolution.dailyledger.")
            }
            entitlement["com.apple.developer.icloud-services"] = ["CloudDocuments"]
            entitlement["com.apple.developer.icloud-container-identifiers"] = [container]
            entitlement["com.apple.developer.ubiquity-container-identifiers"] = [container]
        } else if let customURL {
            guard let data = try? Data(contentsOf: customURL), data.count < 100_000,
                  let chosen = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw LocalSignerError.invalidExplicitEntitlements("Select a readable .entitlements or .plist dictionary.")
            }
            for (key, value) in chosen {
                if let original = entitlement[key],
                   !NSDictionary(dictionary: ["value": original]).isEqual(to: ["value": value]) {
                    throw LocalSignerError.invalidExplicitEntitlements("Signing identity field conflicts with profile: " + key)
                }
                entitlement[key] = value
            }
        }
        for (key, value) in entitlement {
            if key == "com.apple.developer.team-identifier" &&
               profile.permittedEntitlements[key] == nil { continue }
            guard let allowed = profile.permittedEntitlements[key], isAllowed(value, by: allowed) else {
                throw LocalSignerError.invalidExplicitEntitlements("Ad Hoc profile does not authorize: " + key)
            }
        }

        let url = workRoot.appendingPathComponent("NextSigner-Explicit.entitlements")
        let data = try PropertyListSerialization.data(fromPropertyList: entitlement,
                                                       format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func isAllowed(_ actual: String, by allowed: String) -> Bool {
        actual == allowed || allowed == "*" ||
            (allowed.hasSuffix("*") && actual.hasPrefix(String(allowed.dropLast())))
    }

    private func isAllowed(_ actual: Any, by allowed: Any) -> Bool {
        if let a = actual as? String, let b = allowed as? String { return isAllowed(a, by: b) }
        if let a = actual as? [String], let b = allowed as? [String] {
            return a.allSatisfy { item in b.contains { isAllowed(item, by: $0) } }
        }
        if let a = actual as? Bool, let b = allowed as? Bool { return a == b }
        return NSDictionary(dictionary: ["value": actual]).isEqual(to: ["value": allowed])
    }

    /// Do not report iCloud success when a signer copied '*' or removed the
    /// entitlement. Inspect the XML entitlement slot (5) of the actual signed
    /// ARM64 Mach-O, rather than reading the profile's entitlement allow-list.
    private func verifySignedEntitlements(appURL: URL, expectedURL: URL) throws {
        guard let appInfo = try readPlist(appURL.appendingPathComponent("Info.plist")),
              let executable = appInfo["CFBundleExecutable"] as? String else {
            throw LocalSignerError.signedEntitlementsMismatch("CFBundleExecutable")
        }
        let binary = try Data(contentsOf: appURL.appendingPathComponent(executable))
        func u32(_ at: Int, big: Bool = false) -> UInt32? {
            guard at >= 0, at + 4 <= binary.count else { return nil }
            let bytes = [UInt8](binary[at..<(at + 4)])
            if big {
                return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
                       (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            }
            return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) |
                   (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        }
        guard let magic = u32(0), magic == 0xfeedfacf || magic == 0xfeedface,
              let commandCount = u32(16) else {
            throw LocalSignerError.signedEntitlementsMismatch("Mach-O header")
        }
        var command = magic == 0xfeedfacf ? 32 : 28
        var actual: [String: Any]?
        for _ in 0..<Int(commandCount) {
            guard let commandType = u32(command), let commandSize = u32(command + 4),
                  commandSize >= 8 else { break }
            if commandType == 0x1d, let signatureOffset = u32(command + 8),
               let signatureLength = u32(command + 12) {
                let blob = Int(signatureOffset)
                let blobEnd = blob + Int(signatureLength)
                guard blobEnd <= binary.count, u32(blob, big: true) == 0xfade0cc0,
                      let count = u32(blob + 8, big: true) else { break }
                for index in 0..<Int(count) {
                    let base = blob + 12 + index * 8
                    guard let slot = u32(base, big: true),
                          let offset = u32(base + 4, big: true) else { break }
                    let location = blob + Int(offset)
                    if slot == 5, u32(location, big: true) == 0xfade7171,
                       let length = u32(location + 4, big: true) {
                        let start = location + 8
                        let end = location + Int(length)
                        if end <= blobEnd && start < end {
                            actual = try? PropertyListSerialization.propertyList(
                                from: binary.subdata(in: start..<end), format: nil
                            ) as? [String: Any]
                        }
                    }
                }
                break
            }
            command += Int(commandSize)
        }
        guard let actual,
              let expected = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: expectedURL), format: nil
              ) as? [String: Any] else {
            throw LocalSignerError.signedEntitlementsMismatch("code signature")
        }
        for (key, value) in expected {
            guard let signedValue = actual[key],
                  NSDictionary(dictionary: ["value": signedValue]).isEqual(to: ["value": value]) else {
                throw LocalSignerError.signedEntitlementsMismatch(key)
            }
        }
    }

    // MARK: - IPA metadata

    private func findMainApp(in root: URL) throws -> URL {
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        guard let apps = try? FileManager.default.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), let app = apps.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw LocalSignerError.appBundleMissing
        }
        return app
    }

    private func readPlist(_ url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    @discardableResult
    private func updateMainAppMetadata(appURL: URL, appName: String, bundleID: String) throws -> String {
        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard var plist = try readPlist(plistURL) else { throw LocalSignerError.infoPlistMissing }

        let originalBundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        plist["CFBundleIdentifier"] = bundleID
        if !appName.isEmpty {
            plist["CFBundleDisplayName"] = appName
            plist["CFBundleName"] = appName
        }
        try writePlist(plist, to: plistURL)
        return originalBundleID
    }

    private func updateNestedBundleIdentifiers(
        in mainAppURL: URL,
        originalMainBundleID: String,
        newMainBundleID: String
    ) throws -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: mainAppURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var updatedIDs: [String] = []
        var fallbackIndex = 0

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "appex" || (ext == "app" && url.standardizedFileURL != mainAppURL.standardizedFileURL) else { continue }

            enumerator.skipDescendants()
            let plistURL = url.appendingPathComponent("Info.plist")
            guard let current = try? readPlist(plistURL) else { continue }

            let oldID = (current["CFBundleIdentifier"] as? String) ?? ""
            let newID: String
            if !originalMainBundleID.isEmpty, oldID.hasPrefix(originalMainBundleID + ".") {
                newID = newMainBundleID + oldID.dropFirst(originalMainBundleID.count)
            } else {
                fallbackIndex += 1
                let suffix = ext == "appex" ? "extension" : "nestedapp"
                newID = "\(newMainBundleID).\(suffix)\(fallbackIndex)"
            }

            var changed = current
            changed["CFBundleIdentifier"] = newID
            replaceBundleReference(key: "WKCompanionAppBundleIdentifier", in: &changed, oldMainID: originalMainBundleID, newMainID: newMainBundleID)
            replaceBundleReference(key: "WKAppBundleIdentifier", in: &changed, oldMainID: originalMainBundleID, newMainID: newMainBundleID)

            if var extensionInfo = changed["NSExtension"] as? [String: Any],
               var attributes = extensionInfo["NSExtensionAttributes"] as? [String: Any] {
                replaceBundleReference(key: "WKAppBundleIdentifier", in: &attributes, oldMainID: originalMainBundleID, newMainID: newMainBundleID)
                extensionInfo["NSExtensionAttributes"] = attributes
                changed["NSExtension"] = extensionInfo
            }

            try writePlist(changed, to: plistURL)
            updatedIDs.append(newID)
        }
        return updatedIDs
    }

    private func replaceBundleReference(
        key: String,
        in plist: inout [String: Any],
        oldMainID: String,
        newMainID: String
    ) {
        guard let value = plist[key] as? String, !oldMainID.isEmpty else { return }
        if value == oldMainID {
            plist[key] = newMainID
        } else if value.hasPrefix(oldMainID + ".") {
            plist[key] = newMainID + value.dropFirst(oldMainID.count)
        }
    }

    private func writePlist(_ plist: [String: Any], to url: URL) throws {
        let updated = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try updated.write(to: url, options: .atomic)
    }

    // MARK: - Package sanity

    private func fileHasContent(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return false }
        return size > 0
    }

    private func isZIPArchive(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let signature = try? handle.read(upToCount: 4), signature.count >= 4 else { return false }
        let bytes = [UInt8](signature.prefix(4))
        return bytes == [0x50, 0x4B, 0x03, 0x04]
            || bytes == [0x50, 0x4B, 0x05, 0x06]
            || bytes == [0x50, 0x4B, 0x07, 0x08]
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        var result = String(chars)
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "Signed-App" : result
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter
    }()
}
