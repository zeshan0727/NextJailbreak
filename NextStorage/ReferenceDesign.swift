import SwiftUI
import UIKit

/// Visual reference: deep midnight background, blue primary controls,
/// softly raised dark panels, compact storage cards, and five-tab navigation.
enum StorageDesign {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.083)
    static let panel = Color(red: 0.075, green: 0.112, blue: 0.164)
    static let raised = Color(red: 0.100, green: 0.148, blue: 0.213)
    static let border = Color(red: 0.17, green: 0.23, blue: 0.30)
    static let blue = Color(red: 0.035, green: 0.46, blue: 1.0)
    static let cyan = Color(red: 0.10, green: 0.68, blue: 0.98)
    static let purple = Color(red: 0.45, green: 0.27, blue: 0.80)
    static let orange = Color(red: 1.0, green: 0.67, blue: 0.19)
    static let green = Color(red: 0.20, green: 0.83, blue: 0.61)
    static let muted = Color(red: 0.65, green: 0.72, blue: 0.82)
}

struct StorageCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StorageDesign.panel, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(StorageDesign.border.opacity(0.52)))
    }
}

struct StorageSummaryPill: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    var body: some View {
        StorageCard {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 34, height: 39)
                    .foregroundStyle(.white)
                    .background(color, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(StorageDesign.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(value).font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.55)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StorageDonut: View {
    let used: Int64
    let total: Int64
    var diameter: CGFloat = 155
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
    var body: some View {
        ZStack {
            Circle().stroke(StorageDesign.orange, lineWidth: max(12, diameter * 0.1))
            Circle().trim(from: 0, to: fraction)
                .stroke(StorageDesign.blue, style: StrokeStyle(lineWidth: max(12, diameter * 0.1), lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(readable(total)).font(.system(size: 15, weight: .bold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .padding(.horizontal, 8)
                Text("Total").font(.caption2).foregroundStyle(StorageDesign.muted)
            }
        }.frame(width: diameter, height: diameter).padding(6)
    }
}

struct StorageInitialIcon: View {
    let name: String
    let iconPath: String?
    let color: Color
    @State private var appImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(color)
            if let image = appImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 43, height: 43)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        guard appImage == nil, let iconPath else { return }
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: iconPath)) ?? []
        guard let appName = bundles.first(where: { $0.hasSuffix(".app") }) else { return }
        let bundle = iconPath + "/" + appName
        let info = NSDictionary(contentsOfFile: bundle + "/Info.plist")
        guard let icons = info?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let candidates = primary["CFBundleIconFiles"] as? [String] else { return }
        for candidate in candidates.reversed() {
            for ending in ["@3x.png", "@2x.png", ".png"] {
                if let result = UIImage(contentsOfFile: bundle + "/" + candidate + ending) {
                    appImage = result
                    return
                }
            }
        }
    }
}

struct ReferenceOverviewPage: View {
    @EnvironmentObject var model: StorageModel
    @ObservedObject private var photos = LibraryMediaStore.shared
    var measuredApps: Int64 { model.apps.reduce(0) { $0 + $1.total } }
    var activePhotoSize: Int64 { photos.media.reduce(0) { $0 + ($1.byteCount ?? 0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StorageCard {
                    Text("Device Storage").font(.headline)
                    GeometryReader { space in
                        let diameter = min(155, max(104, space.size.width * 0.42))
                        HStack(alignment: .center, spacing: 12) {
                            StorageDonut(used: model.usedSize, total: model.totalSize, diameter: diameter)
                                .frame(width: diameter + 12, height: diameter + 12)
                                .accessibilityLabel("Total storage \(readable(model.totalSize))")
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 7) {
                                    Circle().fill(StorageDesign.blue).frame(width: 9, height: 9).padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Used").font(.caption).foregroundStyle(StorageDesign.muted)
                                        Text(readable(model.usedSize)).font(.subheadline.bold())
                                            .lineLimit(1).minimumScaleFactor(0.65)
                                        Text(String(format:"%.1f%%", model.totalSize > 0 ? Double(model.usedSize)*100/Double(model.totalSize) : 0))
                                            .font(.caption2).foregroundStyle(StorageDesign.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                HStack(alignment: .top, spacing: 7) {
                                    Circle().fill(StorageDesign.orange).frame(width: 9, height: 9).padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Free").font(.caption).foregroundStyle(StorageDesign.muted)
                                        Text(readable(model.availableSize)).font(.subheadline.bold())
                                            .lineLimit(1).minimumScaleFactor(0.65)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 168)
                }

                LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 10),
                                     GridItem(.flexible(minimum: 0), spacing: 10)], spacing: 10) {
                    StorageSummaryPill(title: "Apps", value: model.hasRun ? readable(measuredApps) : "Scan", symbol: "app.fill", color: StorageDesign.blue)
                    StorageSummaryPill(title: "Photos & Videos", value: photos.finished ? readable(activePhotoSize) : "Scan", symbol: "photo.on.rectangle", color: .orange)
                    StorageSummaryPill(title: "System", value: "Not indexed", symbol: "gearshape", color: .gray)
                    StorageSummaryPill(title: "Other", value: "Not indexed", symbol: "square.grid.2x2.fill", color: Color(red: 0.36, green: 0.47, blue: 0.65))
                }

                StorageCard {
                    HStack {
                        Text("Deep Storage Scan").font(.headline)
                        Spacer()
                        Menu {
                            Picker("Scan area", selection: $model.selectedRoot) {
                                Text("Whole device").tag("/")
                                Text("User data & caches").tag("/private/var")
                                Text("App data").tag("/private/var/mobile/Containers/Data/Application")
                                Text("App bundles").tag("/private/var/containers/Bundle/Application")
                            }
                        } label: {
                            Label("Area", systemImage: "chevron.down")
                                .font(.caption).foregroundStyle(StorageDesign.cyan)
                        }
                    }
                    Text("Analyze accessible files and storage containers.")
                        .font(.caption).foregroundStyle(StorageDesign.muted)
                    if model.scanning {
                        ProgressView().tint(StorageDesign.blue)
                        Text(model.currentPath).font(.caption2).foregroundStyle(StorageDesign.muted)
                            .lineLimit(2)
                        Button("Stop Scan", role: .cancel) { model.stop() }
                    } else {
                        Button { model.scan() } label: {
                            Label("Start Deep Scan", systemImage: "magnifyingglass")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent).tint(StorageDesign.blue)
                    }
                    if model.hasRun {
                        Text("\(model.scanned) entries indexed · \(model.denied) inaccessible")
                            .font(.caption2).foregroundStyle(StorageDesign.muted)
                    }
                }

                HStack {
                    Text("Largest Items").font(.headline)
                    Spacer()
                    if model.hasRun { Text("By allocated size").font(.caption).foregroundStyle(StorageDesign.blue) }
                }
                if !model.hasRun {
                    StorageCard {
                        Text("Run Deep Storage Scan to show the largest installed apps and folders.")
                            .font(.subheadline).foregroundStyle(StorageDesign.muted)
                    }
                } else {
                    StorageCard {
                        ForEach(Array(model.largestAppFolders.prefix(10))) { item in
                            NavigationLink {
                                FolderPage(path: item.path)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(StorageDesign.orange)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.catalog.label(for:item.path,fallback:item.name))
                                            .lineLimit(1).font(.subheadline.weight(.medium))
                                            .truncationMode(.middle)
                                        Text(dateString(item.modified)).font(.caption2)
                                            .foregroundStyle(StorageDesign.muted)
                                    }
                                    Spacer()
                                    Text(readable(item.bytes)).font(.caption).foregroundStyle(StorageDesign.muted)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                    Image(systemName:"chevron.right").font(.caption2).foregroundStyle(StorageDesign.muted)
                                }.padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(StorageDesign.border)
                        }
                    }
                }
                if model.limited {
                    Label("Scan reached the indexing limit; results are partial.",systemImage:"exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                }
            }.padding(16)
        }
        .background(StorageDesign.background)
        .navigationTitle("Next Storage")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                NavigationLink { SettingsPage() } label: {
                    Image(systemName:"gearshape.fill").foregroundStyle(StorageDesign.blue)
                }
            }
        }
    }
}

struct ReferenceAppsPage: View {
    @EnvironmentObject var model: StorageModel
    @State private var query = ""
    @State private var order: ListingSort = .largest
    var ordered: [InstalledFootprint] {
        order.orderedApps(model.apps).filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        List {
            Section {
                Picker("Sort apps", selection: $order) {
                    Text("Size").tag(ListingSort.largest)
                    Text("Name").tag(ListingSort.name)
                    Text("Smallest").tag(ListingSort.smallest)
                }.pickerStyle(.segmented)
                .listRowBackground(StorageDesign.panel)
            }
            if !model.hasRun {
                Text("Run a deep storage scan first to identify apps and their sizes.")
                    .foregroundStyle(StorageDesign.muted)
                    .listRowBackground(StorageDesign.panel)
            }
            Section {
                ForEach(ordered) { app in
                    NavigationLink {
                        List {
                            Section("Storage") {
                                LabeledContent("App", value: app.name)
                                LabeledContent("Bundle ID", value: app.id)
                                LabeledContent("App package", value: readable(app.bundleSize))
                                LabeledContent("Documents & data", value: readable(app.dataSize))
                                LabeledContent("Total", value: readable(app.total))
                            }
                            if !app.bundle.isEmpty {
                                Section("App bundle") {
                                    NavigationLink("Browse bundle") { FolderPage(path: app.bundle) }
                                    FilzaAction(path: app.bundle, label:"Open in Filza")
                                }
                            }
                            if let data = app.data {
                                Section("Documents & data") {
                                    NavigationLink("Browse app data") { FolderPage(path: data) }
                                    FilzaAction(path: data, label:"Open in Filza")
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(StorageDesign.background)
                        .navigationTitle(app.name)
                    } label: {
                        HStack(spacing: 13) {
                            StorageInitialIcon(name: app.name, iconPath: app.bundle,
                                color: StorageDesign.blue.opacity(0.85))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(app.id).font(.caption2).foregroundStyle(StorageDesign.muted)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(readable(app.total)).font(.caption).foregroundStyle(StorageDesign.muted)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: 90, alignment: .trailing)
                        }.padding(.vertical, 3)
                    }.listRowBackground(StorageDesign.panel)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StorageDesign.background)
        .searchable(text:$query,prompt:"Search apps...")
        .navigationTitle("Apps")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                NavigationLink { SearchPage() } label: {
                    Image(systemName:"magnifyingglass").foregroundStyle(StorageDesign.blue)
                }
            }
        }
    }
}

struct ReferenceFilesPage: View {
    @EnvironmentObject var model: StorageModel
    @State private var ordering = ListingSort.largest
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName:"folder.fill").foregroundStyle(StorageDesign.blue)
                    VStack(alignment:.leading,spacing:3) {
                        Text("Filesystem").font(.headline)
                        Text("Browse accessible files and directories")
                            .font(.caption).foregroundStyle(StorageDesign.muted)
                    }
                }.padding(.vertical,6)
                NavigationLink { FolderPage(path:"/") } label: {
                    Label("Browse Root Filesystem",systemImage:"externaldrive")
                }
                NavigationLink { FolderPage(path:"/private/var/mobile") } label: {
                    Label("Mobile Data",systemImage:"iphone")
                }
                NavigationLink { FolderPage(path:AppCatalog.dataRoot) } label: {
                    Label("App Containers",systemImage:"square.stack")
                }
            }.listRowBackground(StorageDesign.panel)
            if model.hasRun {
                Section("Largest folders") {
                    ForEach(ordering.ordered(model.files.filter{$0.folder}).prefix(50)) { item in
                        NavigationLink { FolderPage(path:item.path) } label: {
                            HStack {
                                Image(systemName:"folder.fill").foregroundStyle(StorageDesign.orange)
                                Text(model.catalog.label(for:item.path,fallback:item.name)).lineLimit(1)
                                Spacer()
                                Text(readable(item.bytes)).font(.caption).foregroundStyle(StorageDesign.muted)
                            }
                        }
                        .listRowBackground(StorageDesign.panel)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StorageDesign.background)
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                NavigationLink { SearchPage() } label: {
                    Image(systemName:"magnifyingglass").foregroundStyle(StorageDesign.blue)
                }
            }
        }
    }
}
