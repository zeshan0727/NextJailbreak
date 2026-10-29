import Foundation
import Darwin

/// Filesystem-only application and App Group metadata resolver.
/// Never guesses an application name from a UUID: unidentified containers remain explicit.
struct AppContainerIdentity {
    var identifier: String
    var displayName: String
    var bundlePath: String?
    var dataPaths: [String] = []
    var sharedPaths: [String] = []
}

final class AppCatalog {
    private let fm = FileManager.default
    private(set) var identities: [String: AppContainerIdentity] = [:]
    private(set) var containerIDByPath: [String: String] = [:]
    private(set) var namesByPath: [String: String] = [:]
    private(set) var kindByPath: [String: String] = [:]
    private(set) var unresolvedPaths = [String]()
    private(set) var bootstrapPath: String?

    static let bundleRoot = "/private/var/containers/Bundle/Application"
    static let dataRoot = "/private/var/mobile/Containers/Data/Application"
    static let appGroupRoot = "/private/var/mobile/Containers/Shared/AppGroup"
    static let systemGroupRoot = "/private/var/mobile/Containers/Shared/SystemGroup"

    init() { refresh() }

    private func list(_ root: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted()
    }
    private func metadataID(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        guard let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = value as? [String: Any] else { return nil }
        return dict["MCMMetadataIdentifier"] as? String
    }
    private func bundleInfo(_ path: String) -> (String, String)? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Info.plist")),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = value as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String else { return nil }
        let name = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? identifier
        return (identifier, name)
    }
    private func register(bundleID: String, displayName: String, bundlePath: String) {
        let current = identities[bundleID]
        identities[bundleID] = AppContainerIdentity(
            identifier: bundleID,
            displayName: displayName,
            bundlePath: bundlePath,
            dataPaths: current?.dataPaths ?? [],
            sharedPaths: current?.sharedPaths ?? []
        )
        namesByPath[bundlePath] = displayName + " · App"
        kindByPath[bundlePath] = "Application bundle"
        containerIDByPath[bundlePath] = bundleID
    }

    func refresh() {
        identities.removeAll()
        containerIDByPath.removeAll()
        namesByPath.removeAll()
        kindByPath.removeAll()
        unresolvedPaths.removeAll()
        bootstrapPath = nil

        // Installed app packages, including dynamically generated UUID bundle directories.
        for name in list(Self.bundleRoot) {
            let folder = Self.bundleRoot + "/" + name
            if name.hasPrefix(".jbroot-") || name.hasPrefix(".jbroot") {
                bootstrapPath = folder
                namesByPath[folder] = "RootHide Bootstrap"
                kindByPath[folder] = "Jailbreak bootstrap"
                continue
            }
            let candidates = list(folder).filter { $0.hasSuffix(".app") }
            for candidate in candidates {
                if let (id, display) = bundleInfo(folder + "/" + candidate) {
                    register(bundleID: id, displayName: display, bundlePath: folder)
                    break
                }
            }
        }

        // Some pre-installed system applications reside outside UUID bundle folders.
        for root in ["/Applications", "/System/Applications",
                     "/System/Library/CoreServices"] {
            for name in list(root) where name.hasSuffix(".app") {
                let path = root + "/" + name
                if let (id, display) = bundleInfo(path), identities[id] == nil {
                    register(bundleID: id, displayName: display, bundlePath: path)
                }
            }
        }

        // MobileContainerManager metadata maps each random UUID to the real bundle ID.
        for name in list(Self.dataRoot) {
            let path = Self.dataRoot + "/" + name
            if let id = metadataID(path) {
                let old = identities[id]
                let display = old?.displayName ?? id
                var item = old ?? AppContainerIdentity(identifier: id, displayName: display)
                item.dataPaths.append(path)
                identities[id] = item
                containerIDByPath[path] = id
                namesByPath[path] = display + " · Data"
                kindByPath[path] = "Application data"
            } else if name.count >= 20 {
                unresolvedPaths.append(path)
                namesByPath[path] = "Unidentified app data · " + String(name.prefix(8))
                kindByPath[path] = "Metadata unavailable"
            }
        }

        // Shared App Groups are identified by the group ID, not falsely assigned to one app.
        for (root, title) in [(Self.appGroupRoot, "Shared App Group"),
                              (Self.systemGroupRoot, "System Group")] {
            for name in list(root) {
                let path = root + "/" + name
                if let id = metadataID(path) {
                    containerIDByPath[path] = id
                    namesByPath[path] = title + " · " + id
                    kindByPath[path] = title
                } else {
                    namesByPath[path] = title + " · " + String(name.prefix(8))
                    unresolvedPaths.append(path)
                }
            }
        }
    }

    func label(for path: String, fallback: String) -> String {
        if let label = namesByPath[path] { return label }
        if let match = namesByPath.keys.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }),
           let label = namesByPath[match] {
            return fallback == "Library" || fallback == "Documents" || fallback == "Caches"
                ? "\(fallback) · \(label)" : fallback
        }
        return fallback
    }

    func description(for path: String) -> String? {
        if let kind = kindByPath[path] { return kind }
        if let match = kindByPath.keys.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) {
            return kindByPath[match]
        }
        return nil
    }

    func installedFootprints(sizes: [String: Int64]) -> [InstalledFootprint] {
        identities.values.compactMap { app in
            guard app.bundlePath != nil || !app.dataPaths.isEmpty else { return nil }
            let bundle = app.bundlePath ?? ""
            let bundleBytes = sizes[bundle] ?? 0
            let dataBytes = app.dataPaths.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
            return InstalledFootprint(id: app.identifier, name: app.displayName,
                                      bundle: bundle, data: app.dataPaths.first,
                                      bundleSize: bundleBytes, dataSize: dataBytes)
        }.sorted { $0.total > $1.total }
    }
}
