import Foundation

/// A privacy-safe summary of an iOS .ips crash. Raw device identifiers are never sent to AI.
struct CrashSummary {
    let appName: String
    let bundleID: String
    let cause: String
    let usageKey: String?
    let exception: String
    let safeReport: String
}

enum CrashDoctor {
    static func analyze(_ text: String) throws -> CrashSummary {
        guard !text.isEmpty, text.utf8.count < 3_000_000 else {
            throw ForgeError.message("Choose a crash report smaller than 3 MB.")
        }
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        var header = [String: Any]()
        var body = [String: Any]()
        if let first = parts.first,
           let data = String(first).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            header = object
        }
        if parts.count > 1,
           let data = String(parts[1]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            body = object
        } else if header.isEmpty,
                  let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            body = object
        }
        let termination = body["termination"] as? [String: Any] ?? [:]
        let details = (termination["details"] as? [String] ?? []).joined(separator: "\n")
        let type = (body["exception"] as? [String: Any])?["type"] as? String ?? ""
        let bundle = header["bundleID"] as? String ??
            (body["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String ?? ""
        let name = header["app_name"] as? String ?? body["procName"] as? String ?? "Unknown app"
        let textToInspect = details.isEmpty ? String(text.prefix(20_000)) : details
        let key: String?
        if let range = textToInspect.range(of: #"NS[A-Za-z0-9]+UsageDescription"#,
                                            options: .regularExpression) {
            key = String(textToInspect[range])
        } else {
            key = nil
        }
        let cause: String
        if let key {
            cause = "iOS terminated this app because its Info.plist is missing \(key)."
        } else if !details.isEmpty {
            cause = String(details.prefix(1000))
        } else if !type.isEmpty {
            cause = "iOS crash: \(type). A source-level repair may require AI review."
        } else {
            throw ForgeError.message("No recognizable iOS crash information was found in this file.")
        }
        // Deliberately exclude crashReporterKey, UUIDs, device IDs, file paths and user data.
        let safe = "App: \(name)\nBundle: \(bundle)\nException: \(type)\nCause: \(cause)"
        return CrashSummary(appName: name, bundleID: bundle, cause: cause,
                            usageKey: key, exception: type, safeReport: safe)
    }

    static func meaning(for key: String) -> String {
        switch key {
        case "NSPhotoLibraryUsageDescription":
            return "Allow access to your photo library to select photos for this app."
        case "NSPhotoLibraryAddUsageDescription":
            return "Allow this app to save images to your photo library."
        case "NSCameraUsageDescription":
            return "Allow camera access to take photos and capture images in this app."
        case "NSMicrophoneUsageDescription":
            return "Allow microphone access to record audio in this app."
        case "NSLocationWhenInUseUsageDescription":
            return "Allow location access while using this app for location-based features."
        case "NSLocationAlwaysAndWhenInUseUsageDescription":
            return "Allow location access for the app's requested location features."
        case "NSContactsUsageDescription":
            return "Allow contacts access to select contacts in this app."
        case "NSCalendarsUsageDescription":
            return "Allow calendar access for events used in this app."
        case "NSMotionUsageDescription":
            return "Allow motion data access for device motion features."
        case "NSSpeechRecognitionUsageDescription":
            return "Allow speech recognition to transcribe spoken audio."
        default:
            return "Allow access required for the app's requested feature."
        }
    }

    static func addUsageDescriptions(_ project: ForgeProject, keys: [String]) throws -> ForgeProject {
        guard let index = project.files.firstIndex(where: { $0.path == "Info.plist" }) else {
            throw ForgeError.message("The generated project has no Info.plist. Regenerate its scaffold first.")
        }
        var revised = project
        let xml = revised.files[index].content
        guard let data = xml.data(using: .utf8),
              var plist = try PropertyListSerialization.propertyList(from: data,
                                    options: [], format: nil) as? [String: Any] else {
            throw ForgeError.message("Cannot decode the generated Info.plist.")
        }
        for key in keys where !key.isEmpty && key.hasPrefix("NS") && key.hasSuffix("UsageDescription") {
            if plist[key] == nil { plist[key] = meaning(for: key) }
        }
        let encoded = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml, options: 0)
        guard let updated = String(data: encoded, encoding: .utf8) else {
            throw ForgeError.message("Could not encode Info.plist.")
        }
        revised.files[index].content = updated
        return revised
    }

    /// Prevents common privacy crashes before generating the IPA.
    static func preflight(_ project: ForgeProject) throws -> ForgeProject {
        let source = project.files.filter { $0.path.hasSuffix(".swift") }
            .map(\.content).joined(separator: "\n")
        var keys = [String]()
        if ["PHPhotoLibrary", "PHAsset", "PHImageManager", "UIImagePickerController", ".photoLibrary"].contains(where: source.contains) {
            keys.append("NSPhotoLibraryUsageDescription")
        }
        if ["UIImagePickerController.SourceType.camera", ".sourceType = .camera", "AVCaptureDevice"].contains(where: source.contains) {
            keys.append("NSCameraUsageDescription")
        }
        if ["AVAudioRecorder", "AVAudioSession", "SFSpeechRecognizer"].contains(where: source.contains) {
            keys.append("NSMicrophoneUsageDescription")
        }
        if source.contains("CLLocationManager") {
            keys.append("NSLocationWhenInUseUsageDescription")
        }
        return keys.isEmpty ? project : try addUsageDescriptions(project, keys: keys)
    }

    static func patch(_ project: ForgeProject, for crash: CrashSummary) throws -> ForgeProject {
        guard crash.bundleID.isEmpty ||
              crash.bundleID.caseInsensitiveCompare(project.bundleId) == .orderedSame else {
            throw ForgeError.message("The crash is for \(crash.bundleID), but the current project is \(project.bundleId). Select the matching app project before applying the fix.")
        }
        guard let key = crash.usageKey else {
            throw ForgeError.message("No deterministic privacy-key fix found. Use AI Crash Repair.")
        }
        return try addUsageDescriptions(project, keys: [key])
    }
}
