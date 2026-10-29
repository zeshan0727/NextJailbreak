import SwiftUI
import Foundation
import Darwin

private enum Theme {
    static let bg = StorageDesign.background
    static let card = StorageDesign.panel
    static let accent = StorageDesign.blue
    static let muted = StorageDesign.muted
}
func readable(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, size), countStyle: .file)
}
func dateString(_ date: Date?) -> String {
    guard let date = date else { return "Unknown" }
    return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
}

struct DiskItem: Identifiable, Hashable {
    let path: String
    let bytes: Int64
    let modified: Date?
    let folder: Bool
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
struct InstalledFootprint: Identifiable {
    let id: String
    let name: String
    let bundle: String
    let data: String?
    let bundleSize: Int64
    let dataSize: Int64
    var total: Int64 { bundleSize + dataSize }
}
enum ListingSort: String, CaseIterable, Identifiable {
    case largest = "Largest first", smallest = "Smallest first", newest = "Newest first", oldest = "Oldest first", name = "Name"
    var id: String { rawValue }
    func ordered(_ values: [DiskItem]) -> [DiskItem] {
        switch self {
        case .largest: return values.sorted { $0.bytes > $1.bytes }
        case .smallest: return values.sorted { $0.bytes < $1.bytes }
        case .newest: return values.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case .oldest: return values.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        case .name: return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    func orderedApps(_ values: [InstalledFootprint]) -> [InstalledFootprint] {
        switch self {
        case .largest: return values.sorted { $0.total > $1.total }
        case .smallest: return values.sorted { $0.total < $1.total }
        case .newest, .oldest, .name: return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

final class StorageAnalyzer {
    private let fm = FileManager.default
    private let cancelLock = NSLock()
    private var shouldStop = false
    private var filesystemDevice: dev_t = 0
    private var visited = Set<String>()
    private var visitedDirectories = Set<String>()
    private var deniedPaths = [String]()
    private var records = [DiskItem]()
    private var sizes = [String: Int64]()
    private var dates = [String: Date]()
    private var denied = 0
    private var processed = 0
    private var limited = false
    private let excluded = Set(["/dev", "/proc", "/private/var/run", "/private/var/vm"])
    func stop() { cancelLock.lock(); shouldStop = true; cancelLock.unlock() }
    private var stopped: Bool { cancelLock.lock(); defer { cancelLock.unlock() }; return shouldStop }
    struct Result {
        let records: [DiskItem]
        let sizes: [String: Int64]
        let dates: [String: Date]
        let apps: [InstalledFootprint]
        let used: Int64
        let processed: Int
        let denied: Int
        let deniedPaths: [String]
        let limited: Bool
    }
    func run(_ root: String, update: @escaping (Int, String) -> Void) -> Result {
        var rootStat = stat()
        if lstat(root, &rootStat) == 0 {
            filesystemDevice = rootStat.st_dev
            _ = walk(root, depth: 0, update: update)
        } else { denied += 1 }
        let apps = installedApps()
        return Result(records: records, sizes: sizes, dates: dates, apps: apps,
                      used: sizes[root] ?? 0, processed: processed, denied: denied, deniedPaths: deniedPaths, limited: limited || stopped)
    }
    private func walk(_ path: String, depth: Int, update: @escaping (Int, String) -> Void) -> Int64 {
        if stopped { return 0 }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            denied += 1
            if deniedPaths.count < 25 { deniedPaths.append(path + " (errno \(errno))") }
            return 0
        }
        // APFS user data and system root can be different devices.
        // Traverse both; prevent infinite loops via (device,inode) visit keys.
        if excluded.contains(path) { return 0 }
        let kind = mode_t(info.st_mode) & mode_t(S_IFMT)
        if kind == mode_t(S_IFLNK) { return 0 }
        if kind != mode_t(S_IFDIR) && kind != mode_t(S_IFREG) { return 0 }
        if processed >= 950_000 { limited = true; return 0 }
        processed += 1
        if processed % 1500 == 0 { update(processed, path) }
        let size = max(Int64(0), Int64(info.st_blocks) * 512)
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        if kind == mode_t(S_IFREG) {
            if info.st_nlink > 1 {
                let fingerprint = "\(info.st_dev):\(info.st_ino)"
                if !visited.insert(fingerprint).inserted { return 0 }
            }
            if records.count < 550_000 {
                records.append(DiskItem(path: path, bytes: size, modified: modified, folder: false))
            } else { limited = true }
            return size
        }
        var total = size
        var newest = modified
        let fingerprint = "\(info.st_dev):\(info.st_ino)"
        if !visitedDirectories.insert(fingerprint).inserted { return 0 }
        if depth < 128 {
            do {
                let names = try fm.contentsOfDirectory(atPath: path)
                for name in names {
                    if stopped { break }
                    let child = path == "/" ? "/" + name : path + "/" + name
                    total += walk(child, depth: depth + 1, update: update)
                    if let d = dates[child], d > newest { newest = d }
                }
            } catch {
                denied += 1
                if deniedPaths.count < 25 { deniedPaths.append(path + " (\(error.localizedDescription))") }
            }
        } else { limited = true }
        if sizes.count < 550_000 {
            sizes[path] = total
            dates[path] = newest
        } else { limited = true }
        if records.count < 550_000 {
            records.append(DiskItem(path: path, bytes: total, modified: newest, folder: true))
        } else { limited = true }
        return total
    }
    private func installedApps() -> [InstalledFootprint] {
        AppCatalog().installedFootprints(sizes: sizes)
    }

}

@MainActor
final class StorageModel: ObservableObject {
    @Published var selectedRoot = "/"
    @Published var scanning = false
    @Published var files = [DiskItem]()
    @Published var apps = [InstalledFootprint]()
    @Published var folderSizes = [String: Int64]()
    @Published var folderDates = [String: Date]()
    @Published var scanned = 0
    @Published var denied = 0
    @Published var limited = false
    @Published var deniedSamples = [String]()
    @Published var catalog = AppCatalog()
    @Published var largestAppFolders = [DiskItem]()
    @Published var currentPath = ""
    @Published var hasRun = false
    @Published var totalSize: Int64 = 0
    @Published var availableSize: Int64 = 0
    @Published var usedSize: Int64 = 0
    @Published var rootHidePath: String? = nil
    private var analyzer: StorageAnalyzer?
    init() { refresh() }
    func refresh() {
        var system = statfs()
        if statfs("/private/var", &system) == 0 {
            totalSize = Int64(system.f_blocks) * Int64(system.f_bsize)
            availableSize = Int64(system.f_bavail) * Int64(system.f_bsize)
            usedSize = max(0, totalSize - availableSize)
        }
        catalog.refresh()
        rootHidePath = catalog.bootstrapPath
    }
    func scan() {
        guard !scanning else { return }
        refresh()
        scanning = true
        hasRun = false
        scanned = 0
        let path = selectedRoot
        let newAnalyzer = StorageAnalyzer()
        analyzer = newAnalyzer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = newAnalyzer.run(path) { count, current in
                DispatchQueue.main.async { [weak self] in
                    guard self?.analyzer === newAnalyzer else { return }
                    self?.scanned = count
                    self?.currentPath = current
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.analyzer === newAnalyzer else { return }
                self.files = result.records
                self.apps = result.apps
                self.folderSizes = result.sizes
                self.folderDates = result.dates
                self.scanned = result.processed
                self.denied = result.denied
                self.limited = result.limited
                self.deniedSamples = result.deniedPaths
                self.catalog.refresh()
                self.largestAppFolders = result.records.filter { item in
                    guard item.folder else { return false }
                    for root in [AppCatalog.dataRoot, AppCatalog.appGroupRoot, AppCatalog.systemGroupRoot, AppCatalog.bundleRoot] {
                        if item.path.hasPrefix(root + "/") &&
                           !item.path.dropFirst(root.count + 1).contains("/") { return true }
                    }
                    return false
                }.sorted { $0.bytes > $1.bytes }
                self.currentPath = ""
                self.hasRun = true
                self.scanning = false
                self.analyzer = nil
            }
        }
    }
    func stop() { analyzer?.stop() }
    func directory(_ path: String) -> [DiskItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names.compactMap { name in
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            let path = url.path
            var s = stat()
            guard lstat(path, &s) == 0 else { return nil }
            let kind = mode_t(s.st_mode) & mode_t(S_IFMT)
            if kind == mode_t(S_IFLNK) { return nil }
            let folder = kind == mode_t(S_IFDIR)
            let used = folder ? (folderSizes[path] ?? Int64(s.st_blocks) * 512) : Int64(s.st_blocks) * 512
            let d = folderDates[path] ?? Date(timeIntervalSince1970: TimeInterval(s.st_mtimespec.tv_sec))
            return DiskItem(path: path, bytes: used, modified: d, folder: folder)
        }
    }
}

struct DiskRow: View {
    @EnvironmentObject var model: StorageModel
    @EnvironmentObject var filza: FilzaLauncher
    let item: DiskItem
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.folder ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.folder ? .purple : Theme.accent).frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.catalog.label(for: item.path, fallback: item.name))
                    .lineLimit(2).font(.subheadline.weight(.semibold))
                Text((model.catalog.description(for: item.path).map { $0 + " · " } ?? "") + dateString(item.modified))
                    .font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(readable(item.bytes)).font(.caption).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
        .contextMenu {
            FilzaAction(path: item.path)
            Button {
                UIPasteboard.general.string = item.path
            } label: {
                Label("Copy Exact Path", systemImage: "doc.on.doc")
            }
        }
    }
}
struct SortMenu: View {
    @Binding var selected: ListingSort
    var body: some View {
        Menu {
            Picker("Sort", selection: $selected) {
                ForEach(ListingSort.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
        } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
    }
}
struct Metric: View {
    let label: String
    let amount: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
            Text(amount).font(.title3.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
struct OverviewPage: View {
    @EnvironmentObject var model: StorageModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Device storage").font(.largeTitle.bold())
                HStack { Metric(label: "Used", amount: readable(model.usedSize)); Metric(label: "Free", amount: readable(model.availableSize)) }
                ProgressView(value: model.totalSize == 0 ? 0 : Double(model.usedSize) / Double(model.totalSize)).tint(Theme.accent)
                Text("\(readable(model.totalSize)) total capacity").foregroundStyle(Theme.muted).font(.footnote)
                HStack { Metric(label: "Indexed", amount: "\(model.scanned) files & folders"); Metric(label: "Unreadable folders", amount: "\(model.denied)") }
                if model.limited {
                    Label("Scan reached its safety index limit; results are partial.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.footnote)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Deep storage scan").font(.title2.bold())
                    Text("Reads all accessible APFS storage areas. Any paths denied by iOS permissions are reported in diagnostics.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Picker("Area", selection: $model.selectedRoot) {
                        Text("Whole device (accessible)").tag("/")
                        Text("User data & caches").tag("/private/var")
                        Text("App data").tag("/private/var/mobile/Containers/Data/Application")
                        Text("App bundles").tag("/private/var/containers/Bundle/Application")
                    }.pickerStyle(.menu)
                    if model.scanning {
                        ProgressView().tint(Theme.accent)
                        Text(model.currentPath).font(.caption2).lineLimit(2).foregroundStyle(Theme.muted)
                        Button("Stop scan", role: .cancel) { model.stop() }
                    } else {
                        Button { model.scan() } label: {
                            Label("Start Deep Scan", systemImage: "magnifyingglass.circle.fill")
                                .frame(maxWidth: .infinity).padding(12)
                        }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                    }
                }.padding().background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                if model.hasRun {
                    Text("Largest app storage containers").font(.title2.bold())
                    Text("App names from iOS metadata; shared groups stay separate.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    ForEach(model.largestAppFolders.prefix(20)) { item in
                        NavigationLink { FolderPage(path: item.path) } label: { DiskRow(item: item) }
                    }
                    Text("Largest storage areas").font(.title2.bold())
                    ForEach(model.directory(model.selectedRoot).filter { $0.folder }.sorted { $0.bytes > $1.bytes }.prefix(15)) { item in
                        NavigationLink { FolderPage(path: item.path) } label: { DiskRow(item: item) }
                    }
                    if model.denied > 0 {
                        Label("\(model.denied) unreadable paths; details in Settings", systemImage: "lock.shield")
                            .foregroundStyle(.orange).font(.footnote)
                    }
                } else {
                    Text("Start a deep scan to rank applications, directories, and files by allocated space.")
                        .foregroundStyle(Theme.muted)
                }
            }.padding()
        }.navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsPage()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
    }
}
struct AppsPage: View {
    @EnvironmentObject var model: StorageModel
    @State private var search = ""
    @State private var sort: ListingSort = .largest
    var body: some View {
        List {
            if !model.hasRun { Text("Run a Whole device or User data scan to measure application storage.").foregroundStyle(Theme.muted) }
            ForEach(sort.orderedApps(model.apps).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }) { app in
                NavigationLink {
                    List {
                        LabeledContent("Bundle ID", value: app.id)
                        LabeledContent("App package", value: readable(app.bundleSize))
                        LabeledContent("Documents & data", value: readable(app.dataSize))
                        LabeledContent("Total allocated", value: readable(app.total))
                        if !app.bundle.isEmpty {
                            NavigationLink("Browse application bundle") { FolderPage(path: app.bundle) }
                            FilzaAction(path: app.bundle, label: "Open App Bundle in Filza")
                        }
                        if let data = app.data {
                            NavigationLink("Browse app data") { FolderPage(path: data) }
                            FilzaAction(path: data, label: "Open App Data in Filza")
                        }
                    }.navigationTitle(app.name)
                } label: {
                    HStack {
                        Image(systemName: "app.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.subheadline.weight(.semibold))
                            Text(app.id).font(.caption2).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(readable(app.total)).font(.caption).monospacedDigit()
                    }
                }
            }
        }.navigationTitle("Apps")
            .toolbar { SortMenu(selected: $sort) }
            .searchable(text: $search, prompt: "Search installed apps")
    }
}
struct FolderPage: View {
    @EnvironmentObject var model: StorageModel
    let path: String
    @State private var sort: ListingSort = .largest
    var body: some View {
        List {
            Section {
                Text(path).font(.caption2).textSelection(.enabled).foregroundStyle(Theme.muted)
                FilzaAction(path: path).buttonStyle(.borderedProminent)
                Button {
                    UIPasteboard.general.string = path
                } label: { Label("Copy Folder Path", systemImage: "doc.on.doc") }
                if !model.hasRun { Text("Folder totals require a completed scan.").font(.caption).foregroundStyle(.orange) }
            }
            ForEach(sort.ordered(model.directory(path))) { item in
                if item.folder {
                    NavigationLink { FolderPage(path: item.path) } label: { DiskRow(item: item) }
                } else {
                    NavigationLink {
                        FileDetailPage(item: item)
                    } label: { DiskRow(item: item) }
                }
            }
        }.navigationTitle(URL(fileURLWithPath: path).lastPathComponent)
            .toolbar { SortMenu(selected: $sort) }
    }
}
struct FileDetailPage: View {
    let item: DiskItem

    var body: some View {
        List {
            Section("File") {
                LabeledContent("Name", value: item.name)
                LabeledContent("Allocated size", value: readable(item.bytes))
                LabeledContent("Modified", value: dateString(item.modified))
                Text(item.path).font(.footnote).textSelection(.enabled)
            }
            Section("Location") {
                FilzaAction(path: item.path, label: "Go to File in Filza")
                    .buttonStyle(.borderedProminent)
                Button {
                    UIPasteboard.general.string = item.path
                } label: {
                    Label("Copy File Path", systemImage: "doc.on.doc")
                }
            }
        }.navigationTitle("File Details")
    }
}
struct SearchPage: View {
    @EnvironmentObject var model: StorageModel
    @State private var query = ""
    @State private var onlyFiles = false
    @State private var sort: ListingSort = .largest
    var body: some View {
        let matches = model.files.filter {
            (!onlyFiles || !$0.folder) && (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query))
        }
        List {
            if !model.hasRun { Text("Run a scan first to create a deep-search index.").foregroundStyle(Theme.muted) }
            Toggle("Files only", isOn: $onlyFiles).tint(Theme.accent)
            Text("\(matches.count) results").font(.caption).foregroundStyle(Theme.muted)
            ForEach(sort.ordered(matches).prefix(600)) { item in
                if item.folder {
                    NavigationLink { FolderPage(path: item.path) } label: { DiskRow(item: item) }
                } else {
                    NavigationLink {
                        FileDetailPage(item: item)
                    } label: {
                        VStack(alignment: .leading) {
                            DiskRow(item: item)
                            Text(item.path).font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                    }
                }
            }
        }.navigationTitle("Deep Search")
            .searchable(text: $query, prompt: "Filename or path")
            .toolbar { SortMenu(selected: $sort) }
    }
}
struct SettingsPage: View {
    @EnvironmentObject var model: StorageModel
    var body: some View {
        List {
            Section("Compatibility") {
                LabeledContent("Minimum iOS", value: "16.0")
                LabeledContent("Installer", value: "TrollStore")
                LabeledContent("Jailbreak", value: "RootHide")
                LabeledContent("Detected bootstrap", value: model.rootHidePath ?? "Not detected")
                LabeledContent("Process UID", value: "\(getuid())")
                LabeledContent("Effective UID", value: "\(geteuid())")
                Text("Sandbox entitlements do not turn a mobile-user process into root. Unix-restricted directories need a separate trusted privileged service.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Section("Storage diagnostics") {
                LabeledContent("Indexed items", value: "\(model.scanned)")
                LabeledContent("Unreadable directories", value: "\(model.denied)")
                LabeledContent("Unidentified app containers", value: "\(model.catalog.unresolvedPaths.count)")
                if !model.deniedSamples.isEmpty {
                    Text("First blocked paths").font(.subheadline.weight(.semibold))
                    ForEach(model.deniedSamples, id: \.self) { path in
                        Text(path).font(.caption2).textSelection(.enabled).foregroundStyle(.orange)
                    }
                }
                LabeledContent("Scan status", value: model.limited ? "Partial" : model.hasRun ? "Complete" : "Not scanned")
                Button("Refresh access checks") { model.refresh() }
            }
            Section("Privacy") {
                Text("Next Storage reads metadata and allocated block counts only. It does not transmit information, modify files, or automatically delete storage.")
                Text("APFS clones and snapshots can cause differences from the Storage screen in Settings. Shared App Group containers are not attributed to individual apps.")
            }
            Section("Credits") {
                Text("Next Jailbreak · Zeshan0727")
                Text("Next Storage 1.0.7")
            }
        }.navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(StorageDesign.background)
            .tint(StorageDesign.blue)
    }
}
@main
struct NextStorageApp: App {
    @StateObject private var model = StorageModel()
    @StateObject private var filza = FilzaLauncher()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { ReferenceOverviewPage() }.tabItem { Label("Overview", systemImage: "chart.pie.fill") }
                NavigationStack { ReferenceAppsPage() }.tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
                NavigationStack { PhotosStoragePage() }.tabItem { Label("Media", systemImage: "play.rectangle.fill") }
                NavigationStack { ReferenceFilesPage() }.tabItem { Label("Files", systemImage: "folder.fill") }
                NavigationStack { SettingsPage() }.tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }.environmentObject(model)
                .environmentObject(filza)
                .tint(StorageDesign.blue)
                .toolbarBackground(StorageDesign.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .preferredColorScheme(.dark)
                .alert("Filza Could Not Open", isPresented: $filza.showLinkFailure) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("This Filza edition may not support filza:// links. The exact location has been copied. Open Filza and paste this path:\n\n\(filza.fallbackPath)")
                }
        }
    }
}