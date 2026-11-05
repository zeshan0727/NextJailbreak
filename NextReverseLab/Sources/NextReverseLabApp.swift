import SwiftUI
import PhotosUI
import UIKit

@main
struct NextReverseLabApp: App {
    @StateObject private var lab = ReverseLabState()
    var body: some Scene {
        WindowGroup { LabHome().environmentObject(lab) }
    }
}

struct InstalledTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let source: String
}

struct ScanResult {
    var version = "Unknown"
    var build = "Unknown"
    var executable = "Unknown"
    var visited = 0
    var kinds: [String: Int] = [:]
    var examples: [String] = []
    var warning = ""
}

@MainActor
final class ReverseLabState: ObservableObject {
    @Published var apps: [InstalledTarget] = []
    @Published var selected: InstalledTarget?
    @Published var scan: ScanResult?
    @Published var screenshots: [URL] = []
    @Published var observation = ""
    @Published var status = "Ready"
    @Published var showSystem = false

    private func readProperty(_ obj: NSObject, _ key: String) -> Any? {
        let sel = NSSelectorFromString(key)
        guard obj.responds(to: sel) else { return nil }
        return obj.perform(sel)?.takeUnretainedValue()
    }

    func refresh() {
        status = "Discovering installed apps…"
        var found: [String: InstalledTarget] = [:]
        if let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
           let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
           let proxies = readProperty(workspace, "allInstalledApplications") as? [NSObject] {
            for proxy in proxies {
                guard let id = (readProperty(proxy, "bundleIdentifier") as? String),
                      !id.isEmpty else { continue }
                let name = (readProperty(proxy, "localizedName") as? String)
                    ?? (readProperty(proxy, "itemName") as? String) ?? id
                let url = (readProperty(proxy, "bundleURL") as? URL)
                    ?? (readProperty(proxy, "resourcesDirectoryURL") as? URL)
                found[id] = InstalledTarget(id: id, name: name, path: url?.path ?? "", source: "LaunchServices")
            }
        }

        // Read only application bundles. Never visit sandbox documents, keychains or credentials.
        for base in ["/var/containers/Bundle/Application", "/Applications", "/System/Applications"] {
            let parent = URL(fileURLWithPath: base, isDirectory: true)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: nil)) ?? []
            for child in children {
                let bundles: [URL] = child.pathExtension == "app"
                    ? [child]
                    : ((try? FileManager.default.contentsOfDirectory(
                        at: child, includingPropertiesForKeys: nil)) ?? [])
                        .filter { $0.pathExtension == "app" }
                for bundle in bundles {
                    guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any],
                          let id = info["CFBundleIdentifier"] as? String else { continue }
                    let name = (info["CFBundleDisplayName"] as? String)
                        ?? (info["CFBundleName"] as? String) ?? id
                    if let previous = found[id], !previous.path.isEmpty { continue }
                    found[id] = InstalledTarget(id: id, name: name, path: bundle.path, source: "Bundle filesystem")
                }
            }
        }
        apps = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        status = apps.isEmpty ? "No applications exposed. Check jailbreak permissions." : "Found \(apps.count) application records"
    }

    func select(_ target: InstalledTarget) {
        selected = target
        scan = nil
        screenshots = []
        observation = ""
        status = "Selected \(target.name)"
    }

    func inspect() {
        guard let target = selected else { return }
        var result = ScanResult()
        guard !target.path.isEmpty else {
            result.warning = "App bundle path was not exposed. Jailbreak access not verified."
            scan = result
            return
        }
        let root = URL(fileURLWithPath: target.path, isDirectory: true)
        let info = (NSDictionary(contentsOf: root.appendingPathComponent("Info.plist")) as? [String: Any]) ?? [:]
        result.version = (info["CFBundleShortVersionString"] as? String) ?? "Unknown"
        result.build = (info["CFBundleVersion"] as? String) ?? "Unknown"
        result.executable = (info["CFBundleExecutable"] as? String) ?? "Unknown"
        if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]) {
            for case let file as URL in files {
                result.visited += 1
                if result.visited >= 5000 { result.warning = "Scan truncated at 5,000 entries."; break }
                let extensionName = file.pathExtension.lowercased()
                let key = extensionName.isEmpty ? "(none)" : "." + extensionName
                result.kinds[key, default: 0] += 1
                if result.examples.count < 120,
                   ["png","jpg","jpeg","car","nib","storyboardc","strings","json","plist","ttf","otf","framework"].contains(extensionName) {
                    result.examples.append(String(file.path.dropFirst(root.path.count)))
                }
            }
        } else { result.warning = "Cannot enumerate this app bundle using available permissions." }
        scan = result
        status = "Inspected \(result.visited) bundle entries"
    }

    func importScreenshots(_ picks: [PhotosPickerItem]) async {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in picks.prefix(12) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let picture = UIImage(data: data),
                  let image = picture.jpegData(compressionQuality: 0.85) else { continue }
            let url = folder.appendingPathComponent(UUID().uuidString + ".jpg")
            if (try? image.write(to: url, options: .atomic)) != nil { screenshots.append(url) }
        }
        status = "Imported \(screenshots.count) screen reference images"
    }

    var report: String {
        let app = selected
        let version = scan?.version ?? "Unscanned"
        let files = scan?.visited ?? 0
        let extensions = scan?.kinds.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ") ?? "(not scanned)"
        let resources = scan?.examples.joined(separator: "\n- ") ?? "(not scanned)"
        let shots = screenshots.enumerated().map { "Screen \($0.offset + 1): \($0.element.lastPathComponent)" }
            .joined(separator: "\n")
        return """
        # NEXT Reverse Lab — Reconstruction Evidence
        Application: \(app?.name ?? "Not selected")
        Reference bundle ID: \(app?.id ?? "Unknown")
        Installed bundle path: \(app?.path ?? "Unknown")
        Source of discovery: \(app?.source ?? "Unknown")
        Version: \(version)
        Build: \(scan?.build ?? "Unknown")
        Main executable: \(scan?.executable ?? "Unknown")
        Inspected entries: \(files)
        Resource type counts: \(extensions)
        Resource path examples:
        - \(resources)
        Scan limitation: \(scan?.warning ?? "No additional warnings")

        Screenshot files (attach these images with this report):
        \(shots.isEmpty ? "None" : shots)

        User observations of navigation and functions:
        \(observation.isEmpty ? "Not supplied." : observation)

        TASK:
        Rebuild an independent iOS 16+ SwiftUI app with a similar observed design and
        tested user journeys, based on the attached screenshots and verified evidence.
        Use original branding and code, with a NEW bundle identifier. Create a complete
        Xcode project and GitHub macOS build workflow. Separate observed behavior from
        assumptions. DO NOT claim to have extracted original source code, hidden APIs,
        private data, account credentials, or unobserved functions.
        """
    }

    func exportFiles() -> [URL] {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let doc = folder.appendingPathComponent("NextReverseLab-Reconstruction-Prompt.md")
        do {
            try report.write(to: doc, atomically: true, encoding: .utf8)
            return [doc] + screenshots
        } catch { status = "Export failed: \(error.localizedDescription)"; return [] }
    }
}

struct LabHome: View {
    @EnvironmentObject private var model: ReverseLabState
    var body: some View {
        TabView {
            AppsTab().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            EvidenceTab().tabItem { Label("Screens", systemImage: "camera.viewfinder") }
            PromptTab().tabItem { Label("Prompt", systemImage: "doc.text") }
        }.onAppear { if model.apps.isEmpty { model.refresh() } }
    }
}

private struct LabBrand: View {
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT").font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black, in: RoundedRectangle(cornerRadius: 10))
                Text("REVERSE LAB").font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}

private struct AppsTab: View {
    @EnvironmentObject private var model: ReverseLabState
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabBrand(subtitle: "Inspect an installed app's accessible package and collect UI evidence.")
                    Label(model.status, systemImage: "info.circle").font(.footnote)
                    Toggle("Show system apps", isOn: $model.showSystem)
                    Button { model.refresh() } label: { Label("Refresh app list", systemImage: "arrow.clockwise") }
                }
                if let app = model.selected {
                    Section("Selected · \(app.name)") {
                        Text(app.id).font(.caption).textSelection(.enabled)
                        Button { model.inspect() } label: {
                            Label("Inspect app bundle", systemImage: "doc.text.magnifyingglass")
                        }
                        if let scan = model.scan {
                            LabeledContent("Version", value: scan.version)
                            LabeledContent("Inspected", value: "\(scan.visited) entries")
                            LabeledContent("Resource types", value: "\(scan.kinds.count)")
                            if !scan.warning.isEmpty {
                                Text(scan.warning).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Section("Installed applications") {
                    ForEach(model.apps.filter { app in
                        (model.showSystem || !app.id.hasPrefix("com.apple.")) &&
                        (search.isEmpty || app.name.localizedCaseInsensitiveContains(search) ||
                         app.id.localizedCaseInsensitiveContains(search))
                    }) { app in
                        Button { model.select(app) } label: {
                            HStack {
                                Image(systemName: "app.fill").foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).foregroundStyle(.primary).font(.body.weight(.medium))
                                    Text(app.id).foregroundStyle(.secondary).font(.caption).lineLimit(1)
                                }
                                Spacer()
                                if model.selected?.id == app.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("Applications")
                .searchable(text: $search, prompt: "Name or bundle identifier")
        }
    }
}

private struct EvidenceTab: View {
    @EnvironmentObject private var model: ReverseLabState
    @State private var selectedImages: [PhotosPickerItem] = []
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabBrand(subtitle: "Screenshots are imported explicitly; no other app is monitored.")
                    Text(model.selected?.name ?? "Select an application first")
                        .font(.headline)
                    PhotosPicker(selection: $selectedImages, maxSelectionCount: 12, matching: .images) {
                        Label("Import screen captures", systemImage: "photo.on.rectangle")
                    }.disabled(model.selected == nil)
                }
                Section("Observed functions and navigation") {
                    TextEditor(text: $model.observation)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if model.observation.isEmpty {
                                Text("Describe buttons, screens, transitions, and what each action does.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Section("Screenshots · \(model.screenshots.count)") {
                    ForEach(model.screenshots, id: \.self) { url in
                        HStack {
                            if let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(width: 80, height: 138)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent).font(.caption)
                                Button("Remove", role: .destructive) {
                                    model.screenshots.removeAll { $0 == url }
                                    try? FileManager.default.removeItem(at: url)
                                }.font(.footnote)
                            }
                        }
                    }
                }
            }.navigationTitle("Screen Evidence")
                .onChange(of: selectedImages) { picks in
                    Task { await model.importScreenshots(picks); selectedImages = [] }
                }
        }
    }
}

private struct PromptTab: View {
    @EnvironmentObject private var model: ReverseLabState
    @State private var files: [URL] = []
    @State private var sharing = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabBrand(subtitle: "Generate a reconstruction prompt and share the screenshots.")
                    Button {
                        UIPasteboard.general.string = model.report
                        model.status = "Prompt copied"
                    } label: { Label("Copy reconstruction prompt", systemImage: "doc.on.doc") }
                        .disabled(model.selected == nil)
                    Button {
                        files = model.exportFiles()
                        sharing = !files.isEmpty
                    } label: { Label("Export prompt + screenshots", systemImage: "square.and.arrow.up") }
                        .disabled(model.selected == nil)
                }
                Section("Prompt preview") {
                    Text(model.report).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section("First-test limitations") {
                    Text("App bundle inspection is best-effort. This version does not decrypt binaries, trace hidden functions, read private app data, or capture live UI from another app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Build Prompt")
                .sheet(isPresented: $sharing) { SharingController(urls: files) }
        }
    }
}

private struct SharingController: UIViewControllerRepresentable {
    var urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}