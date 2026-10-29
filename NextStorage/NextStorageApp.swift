import SwiftUI
import Foundation
import Darwin

private enum Theme {
    static let bg = Color(red: 0.055, green: 0.082, blue: 0.145)
    static let card = Color(red: 0.115, green: 0.16, blue: 0.24)
    static let accent = Color(red: 0.3, green: 0.92, blue: 0.77)
    static let muted = Color(red: 0.68, green: 0.75, blue: 0.82)
}
private func readable(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, size), countStyle: .file)
}
private func dateString(_ date: Date?) -> String {
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
    private var records = [DiskItem]()
    private var sizes = [String: Int64]()
    private var dates = [String: Date]()
    private var denied = 0
    private var processed = 0
    private var limited = false
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
                      used: sizes[root] ?? 0, processed: processed, denied: denied, limited: limited)
    }
    private func walk(_ path: String, depth: Int, update: @escaping (Int, String) -> Void) -> Int64 {
        if stopped { return 0 }
        var info = stat()
        guard lstat(path, &info) == 0 else { denied += 1; return 0 }
        if info.st_dev != filesystemDevice { return 0 }
        let kind = mode_t(info.st_mode) & mode_t(S_IFMT)
        if kind == mode_t(S_IFLNK) { return 0 }
        if kind != mode_t(S_IFDIR) && kind != mode_t(S_IFREG) { return 0 }
        if processed >= 350_000 { limited = true; return 0 }
        processed += 1
        if processed % 1500 == 0 { update(processed, path) }
        let size = max(Int64(0), Int64(info.st_blocks) * 512)
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        if kind == mode_t(S_IFREG) {
            if info.st_nlink > 1 {
                let fingerprint = "\(info.st_dev):\(info.st_ino)"
                if !visited.insert(fingerprint).inserted { return 0 }
            }
            if records.count < 200_000 {
                records.append(DiskItem(path: path, bytes: size, modified: modified, folder: false))
            } else { limited = true }
            return size
        }
        var total = size
        var newest = modified
        if depth < 70 {
            do {
                let names = try fm.contentsOfDirectory(atPath: path)
                for name in names {
                    if stopped { break }
                    let child = path == "/" ? "/" + name : path + "/" + name
                    total += walk(child, depth: depth + 1, update: update)
                    if let d = dates[child], d > newest { newest = d }
                }
            } catch { denied += 1 }
        } else { limited = true }
        if sizes.count < 200_000 {
            sizes[path] = total
            dates[path] = newest
        } else { limited = true }
        if records.count < 200_000 {
            records.append(DiskItem(path: path, bytes: total, modified: newest, folder: true))
        } else { limited = true }
        return total
    }
    private func installedApps() -> [InstalledFootprint] {
        let base = "/private/var/containers/Bundle/Application"
        let dataBase = "/private/var/mobile/Containers/Data/Application"
        let dataDirs = (try? fm.contentsOfDirectory(atPath: dataBase)) ?? []
        var dataMap = [String: String]()
        for uuid in dataDirs {
            let path = dataBase + "/" + uuid
            let metadata = path + "/.com.apple.mobile_container_manager.metadata.plist"
            if let dict = NSDictionary(contentsOfFile: metadata),
               let id = dict["MCMMetadataIdentifier"] as? String { dataMap[id] = path }
        }
        var output = [InstalledFootprint]()
        for uuid in (try? fm.contentsOfDirectory(atPath: base)) ?? [] {
            let path = base + "/" + uuid
            guard let appName = (try? fm.contentsOfDirectory(atPath: path))?.first(where: { $0.hasSuffix(".app") }),
                  let info = NSDictionary(contentsOfFile: path + "/" + appName + "/Info.plist"),
                  let bundle = info["CFBundleIdentifier"] as? String else { continue }
            let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? appName
            let data = dataMap[bundle]
            output.append(InstalledFootprint(id: bundle, name: name, bundle: path, data: data,
                                              bundleSize: sizes[path] ?? 0,
                                              dataSize: data.flatMap { sizes[$0] } ?? 0))
        }
        return output.sorted { $0.total > $1.total }
    }
}

@MainActor
final class StorageModel: ObservableObject {
    @Published var selectedRoot = "/private/var"
    @Published var scanning = false
    @Published var files = [DiskItem]()
    @Published var apps = [InstalledFootprint]()
    @Published var folderSizes = [String: Int64]()
    @Published var folderDates = [String: Date]()
    @Published var scanned = 0
    @Published var denied = 0
    @Published var limited = false
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
        let base = "/private/var/containers/Bundle/Application"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: base) {
            rootHidePath = names.first(where: { $0.hasPrefix(".jbroot-") }).map { base + "/" + $0 }
        }
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
    let item: DiskItem
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.folder ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.folder ? .purple : Theme.accent).frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).lineLimit(1).font(.subheadline.weight(.semibold))
                Text(dateString(item.modified)).font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Text(readable(item.bytes)).font(.caption).monospacedDigit().foregroundStyle(Theme.muted)
        }.padding(.vertical, 4)
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
                    Picker("Area", selection: $model.selectedRoot) {
                        Text("User data & caches").tag("/private/var")
                        Text("Entire filesystem").tag("/")
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
                    Text("Largest scanned folders").font(.title2.bold())
                    ForEach(model.directory(model.selectedRoot).filter { $0.folder }.sorted { $0.bytes > $1.bytes }.prefix(15)) { item in
                        NavigationLink { FolderPage(path: item.path) } label: { DiskRow(item: item) }
                    }
                } else {
                    Text("Start a deep scan to rank applications, directories, and files by allocated space.")
                        .foregroundStyle(Theme.muted)
                }
            }.padding()
        }.navigationTitle("Overview")
    }
}
struct AppsPage: View {
    @EnvironmentObject var model: StorageModel
    @State private var search = ""
    @State private var sort: ListingSort = .largest
    var body: some View {
        List {
            if !model.hasRun { Text("Run a scan of User data & caches to measure application storage.").foregroundStyle(Theme.muted) }
            ForEach(sort.orderedApps(model.apps).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }) { app in
                NavigationLink {
                    List {
                        LabeledContent("Bundle ID", value: app.id)
                        LabeledContent("App package", value: readable(app.bundleSize))
                        LabeledContent("Documents & data", value: readable(app.dataSize))
                        LabeledContent("Total allocated", value: readable(app.total))
                        NavigationLink("Browse application bundle") { FolderPage(path: app.bundle) }
                        if let data = app.data { NavigationLink("Browse app data") { FolderPage(path: data) } }
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
                if !model.hasRun { Text("Folder totals require a completed scan.").font(.caption).foregroundStyle(.orange) }
            }
            ForEach(sort.ordered(model.directory(path))) { item in
                if item.folder {
                    NavigationLink { FolderPage(path: item.path) } label: { DiskRow(item: item) }
                } else {
                    NavigationLink {
                        List {
                            LabeledContent("Name", value: item.name)
                            LabeledContent("Allocated", value: readable(item.bytes))
                            LabeledContent("Modified", value: dateString(item.modified))
                            Text(item.path).font(.footnote).textSelection(.enabled)
                        }.navigationTitle("File details")
                    } label: { DiskRow(item: item) }
                }
            }
        }.navigationTitle(URL(fileURLWithPath: path).lastPathComponent)
            .toolbar { SortMenu(selected: $sort) }
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
                    VStack(alignment: .leading) {
                        DiskRow(item: item)
                        Text(item.path).font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
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
            }
            Section("Storage diagnostics") {
                LabeledContent("Indexed items", value: "\(model.scanned)")
                LabeledContent("Unreadable directories", value: "\(model.denied)")
                LabeledContent("Scan status", value: model.limited ? "Partial" : model.hasRun ? "Complete" : "Not scanned")
                Button("Refresh access checks") { model.refresh() }
            }
            Section("Privacy") {
                Text("Next Storage reads metadata and allocated block counts only. It does not transmit information, modify files, or automatically delete storage.")
                Text("APFS clones and snapshots can cause differences from the Storage screen in Settings. Shared App Group containers are not attributed to individual apps.")
            }
            Section("Credits") {
                Text("Next Jailbreak · Zeshan0727")
                Text("Next Storage 1.0.0")
            }
        }.navigationTitle("Settings")
    }
}
@main
struct NextStorageApp: App {
    @StateObject private var model = StorageModel()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { OverviewPage() }.tabItem { Label("Overview", systemImage: "chart.pie.fill") }
                NavigationStack { AppsPage() }.tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
                NavigationStack { FolderPage(path: "/private/var") }.tabItem { Label("Explorer", systemImage: "folder.fill") }
                NavigationStack { SearchPage() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
                NavigationStack { SettingsPage() }.tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }.environmentObject(model).tint(Theme.accent).preferredColorScheme(.dark)
        }
    }
}