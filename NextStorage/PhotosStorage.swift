import SwiftUI
import Photos
import AVKit
import CryptoKit
import UIKit

// Only small value types are retained. Never retain all PHAsset or
// PHAssetResource instances and never read full media bytes during scanning.
struct LibraryMedia: Identifiable {
    let id: String
    let filename: String
    let created: Date?
    let video: Bool
    let duration: Double
    var byteCount: Int64?
    var isEstimated: Bool = false
    var verifiedPath: String?
}

private struct LocalFile {
    let path: String
    let bytes: Int64
    var isAmbiguous: Bool = false
}

private final class ScanFlag {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

private enum PhotosDiskIndex {
    static let localRoot = URL(fileURLWithPath: "/private/var/mobile/Media/DCIM", isDirectory: true)

    // Metadata only: no file bytes, thumbnail creation or cryptographic hashing.
    // Store at most one candidate plus an ambiguity flag for each name.
    static func build(flag: ScanFlag) -> [String: LocalFile] {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: localRoot,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [:] }
        var found = [String: LocalFile]()
        var inspected = 0
        while let url = files.nextObject() as? URL {
            if flag.cancelled { break }
            inspected += 1
            if inspected > 200_000 { break } // bounded scan, reported as partial below
            guard let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  attributes.isRegularFile == true,
                  let bytes = attributes.fileSize else { continue }
            let name = url.lastPathComponent.lowercased()
            if var existing = found[name] {
                existing.isAmbiguous = true
                found[name] = existing
            } else {
                found[name] = LocalFile(path: url.path, bytes: Int64(bytes))
            }
        }
        return found
    }

    static func preferred(_ asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        if asset.mediaType == .video {
            return resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video })
        }
        return resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
    }

    // Explicit, on-demand verification of one selected item only.
    // SHA256 is incremental and never buffers entire videos into memory.
    static func photoBytesAndDigest(_ resource: PHAssetResource) -> (Int64, String)? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var bytes: Int64 = 0
        var sha = SHA256()
        var succeeded = false
        let request = PHAssetResourceManager.default().requestData(
            for: resource, options: options, dataReceivedHandler: { chunk in
                lock.lock()
                bytes += Int64(chunk.count)
                sha.update(data: chunk)
                lock.unlock()
            }, completionHandler: { error in
                lock.lock()
                succeeded = error == nil
                lock.unlock()
                semaphore.signal()
            })
        guard semaphore.wait(timeout: .now() + 75) == .success else {
            PHAssetResourceManager.default().cancelDataRequest(request)
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        guard succeeded else { return nil }
        return (bytes, sha.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func digestFile(at path: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var sha = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 512 * 1024) else { return nil }
            if chunk.isEmpty { break }
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifySelected(_ id: String) -> (Int64?, String?) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              let resource = preferred(asset) else { return (nil, nil) }
        guard let (bytes, hash) = photoBytesAndDigest(resource) else { return (nil, nil) }

        let base = localRoot
        // Enumerate only the few same-name local candidates for this item;
        // this verification is never performed on the entire library.
        guard let enumerator = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return (bytes, nil) }
        var match: String?
        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent.caseInsensitiveCompare(resource.originalFilename) == .orderedSame,
                  let props = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  props.isRegularFile == true,
                  props.fileSize.map(Int64.init) == bytes else { continue }
            guard digestFile(at: url.path) == hash else { continue }
            if match != nil { return (bytes, nil) } // ambiguous; don't guess
            match = url.path
        }
        return (bytes, match)
    }
}

@MainActor
final class LibraryMediaStore: ObservableObject {
    @Published private(set) var media = [LibraryMedia]()
    @Published private(set) var permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var running = false
    @Published private(set) var finished = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var status = ""
    @Published private(set) var inspectingID: String?
    @Published var alertError: String?
    private var flag: ScanFlag?
    private var generation = UUID()

    var measuredSize: Int64 { media.reduce(Int64(0)) { $0 + ($1.byteCount ?? 0) } }
    var unknown: Int { media.reduce(0) { $0 + ($1.byteCount == nil ? 1 : 0) } }
    var isAllowed: Bool { permission == .authorized || permission == .limited }

    func requestAndScan() {
        permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if isAllowed { scan(); return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async { [weak self] in
                self?.permission = status
                if self?.isAllowed == true { self?.scan() }
            }
        }
    }

    func cancel() {
        flag?.stop()
        generation = UUID()
        running = false
        finished = false
        status = "Stopped. No partial or incorrectly sized results were published."
    }

    func scan() {
        guard isAllowed, !running else { return }
        running = true
        finished = false
        media = []
        done = 0
        total = 0
        status = "Indexing local file metadata…"
        let activeFlag = ScanFlag()
        flag = activeFlag
        let gen = UUID()
        generation = gen

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Use PhotoKit's asset resource catalog, not a partial DCIM index.
            // Access only metadata; no hashes, downloads, or decoded images.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.status = "Sizing every Photos resource from metadata…"
            }
            let all = PHAsset.fetchAssets(with: nil)
            let maxIndexed = 150_000
            let bound = min(all.count, maxIndexed)
            var entries = [LibraryMedia]()
            entries.reserveCapacity(min(bound, 20_000))
            var localCount = 0
            var progress = 0
            for idx in 0..<bound {
                if activeFlag.cancelled { return }
                autoreleasepool {
                    let asset = all.object(at: idx)
                    guard asset.mediaType == .image || asset.mediaType == .video else { return }
                    let resource = PhotosDiskIndex.preferred(asset)
                    let name = resource?.originalFilename ?? (asset.mediaType == .video ? "Video" : "Photo")
                    // Count all distinct photo/video resources in the asset
                    // (Live Photo companion movies, edited originals, RAW).
                    // KVC is exception-guarded in the Objective-C bridge.
                    var totalBytes: Int64 = 0
                    var known = 0
                    for entry in PHAssetResource.assetResources(for: asset) {
                        if let bytes = NextPhotoResourceBytes(entry)?.int64Value,
                            bytes > 0, totalBytes <= Int64.max - bytes {
                            totalBytes += bytes
                            known += 1
                        }
                    }
                    let size: Int64? = known == 0 ? nil : totalBytes
                    if size != nil { localCount += 1 }
                    entries.append(LibraryMedia(id: asset.localIdentifier, filename: name,
                                                created: asset.creationDate,
                                                video: asset.mediaType == .video,
                                                duration: asset.duration,
                                                byteCount: size,
                                                isEstimated: size != nil,
                                                verifiedPath: nil))
                }
                progress += 1
                if progress % 1000 == 0 {
                    let count = progress
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == gen else { return }
                        self.done = count
                        self.total = bound
                    }
                }
            }
            if activeFlag.cancelled { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.media = entries  // exactly ONE full-array UI publication
                self.done = bound
                self.total = all.count
                self.finished = true
                self.running = false
                self.flag = nil
                self.status = all.count > maxIndexed
                    ? "Index safety limit: scanned \(bound) of \(all.count) assets."
                    : "Sized \(localCount) of \(entries.count) assets from Photos resource metadata. Verify an individual original for an exact Filza path."
            }
        }
    }

    func inspect(_ id: String) {
        guard inspectingID == nil, !running, media.contains(where: { $0.id == id }) else { return }
        inspectingID = id
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = PhotosDiskIndex.verifySelected(id)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inspectingID = nil
                guard let index = self.media.firstIndex(where: { $0.id == id }) else { return }
                if let size = result.0 {
                    self.media[index].byteCount = size
                    self.media[index].isEstimated = false
                    self.media[index].verifiedPath = result.1
                    if result.1 == nil {
                        self.alertError = "Exact file size verified. No unique matching local DCIM file was found for Filza; the location will not be guessed."
                    }
                } else {
                    self.alertError = "Could not measure this asset locally. It may be stored in iCloud, protected, or temporarily unavailable."
                }
            }
        }
    }

    func delete(_ id: String) {
        guard !running, isAllowed else { alertError = "Complete the scan and grant Photos access first."; return }
        let target = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = target.firstObject else { alertError = "This file no longer exists."; return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }, completionHandler: { [weak self] success, error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if success {
                    self.media.removeAll { $0.id == id }
                } else {
                    self.alertError = error?.localizedDescription ?? "Photos could not delete this item."
                }
            }
        })
    }
}

private enum MediaKind: String, CaseIterable {
    case all = "All", photos = "Photos", videos = "Videos"
}
private enum MediaSort: String, CaseIterable {
    case largest = "Largest", smallest = "Smallest", newest = "Newest", oldest = "Oldest", name = "Filename"
}

struct PhotosStoragePage: View {
    @StateObject private var store = LibraryMediaStore()
    @State private var kind = MediaKind.all
    @State private var sort = MediaSort.largest
    @State private var search = ""
    @State private var selection: LibraryMedia?
    @State private var deleteID: String?

    private var matches: [LibraryMedia] {
        let all = store.media.filter { media in
            (kind == .all || (kind == .videos && media.video) || (kind == .photos && !media.video))
            && (search.isEmpty || media.filename.localizedCaseInsensitiveContains(search))
        }
        switch sort {
        case .largest: return all.sorted { ($0.byteCount ?? -1) > ($1.byteCount ?? -1) }
        case .smallest: return all.sorted { ($0.byteCount ?? Int64.max) < ($1.byteCount ?? Int64.max) }
        case .newest: return all.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .oldest: return all.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
        case .name: return all.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        }
    }

    var body: some View {
        let shown = matches
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Photos & Videos").font(.title2.bold())
                        Text("\(store.media.count) indexed assets")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.mint)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Photos library resources").font(.caption).foregroundStyle(.secondary)
                        Text(readable(store.measuredSize)).font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Unknown size").font(.caption).foregroundStyle(.secondary)
                        Text("\(store.unknown)").font(.headline)
                    }
                }
                Text("Counts reported Photos resources including videos, Live Photo companions and edited copies, even outside accessible DCIM. No full files are read in this scan. Library resource totals can differ from on-device Photos storage due to APFS, caching and iCloud.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.permission == .limited {
                    Text("Limited Photos access: only selected items are indexed.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if store.running {
                    ProgressView(value: Double(store.done), total: Double(max(1, store.total)))
                    Button("Stop Scan", role: .cancel) { store.cancel() }
                } else {
                    Button { store.requestAndScan() } label: {
                        Label(store.media.isEmpty ? "Scan Photos & Videos" : "Rescan Photos & Videos",
                              systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderedProminent)
                }
                if !store.status.isEmpty {
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.isAllowed && !store.running {
                Section {
                    Picker("Media", selection: $kind) {
                        ForEach(MediaKind.allCases, id: \.self) { entry in Text(entry.rawValue).tag(entry) }
                    }.pickerStyle(.segmented)
                    Picker("Sort", selection: $sort) {
                        ForEach(MediaSort.allCases, id: \.self) { entry in Text(entry.rawValue).tag(entry) }
                    }
                    Text("\(shown.count) results · showing the first \(min(250, shown.count)). Refine the search for more.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Files") {
                    ForEach(Array(shown.prefix(250))) { item in
                        Button { selection = item } label: { MediaListRow(item: item) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let path = item.verifiedPath {
                                    FilzaAction(path: path, label: "Open Exact File in Filza")
                                }
                                Button(role: .destructive) {
                                    deleteID = item.id
                                } label: { Label("Delete from Photos…", systemImage: "trash") }
                            }
                    }
                }
            } else if !store.isAllowed {
                Section {
                    Text("Allow Photos access to inspect your local library.")
                    if store.permission == .restricted || store.permission == .denied {
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Media")
        .searchable(text: $search, prompt: "Search photo or video filename")
        .sheet(item: $selection) { item in
            NavigationStack {
                MediaDetailsPage(itemID: item.id, fallback: item, store: store) {
                    selection = nil
                    deleteID = item.id
                }
            }
        }
        .confirmationDialog("Move to Recently Deleted?", isPresented: Binding(
            get: { deleteID != nil },
            set: { if !$0 { deleteID = nil } }
        ), titleVisibility: .visible) {
            Button("Delete from Photos", role: .destructive) {
                if let id = deleteID { store.delete(id) }
                deleteID = nil
            }
            Button("Cancel", role: .cancel) { deleteID = nil }
        } message: {
            Text("iOS also asks permission to delete. Files are not directly unlinked from DCIM.")
        }
        .alert("Media", isPresented: Binding(
            get: { store.alertError != nil },
            set: { if !$0 { store.alertError = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertError = nil }
        } message: {
            Text(store.alertError ?? "")
        }
    }
}

private struct MediaListRow: View {
    let item: LibraryMedia
    var body: some View {
        HStack(spacing: 10) {
            MediaThumbnail(identifier: item.id, video: item.video)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: item.video ? "video.fill" : "photo.fill")
                    Text(dateString(item.created))
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.byteCount.map(readable) ?? "Unknown")
                    .font(.caption).foregroundStyle(.primary).monospacedDigit()
                if item.isEstimated {
                    Text("PhotoKit").font(.caption2).foregroundStyle(.orange)
                } else if item.verifiedPath != nil {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.mint)
                }
            }
        }.padding(.vertical, 2)
    }
}

private struct MediaThumbnail: View {
    let identifier: String
    let video: Bool
    @State private var image: UIImage?
    @State private var request = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: video ? "film" : "photo")
                    .font(.title2).foregroundStyle(.secondary)
            }
        }
        .clipped()
        .onAppear {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            request = PHImageManager.default().requestImage(for: asset,
                targetSize: CGSize(width: 150, height: 150),
                contentMode: .aspectFill, options: options) { result, _ in
                    DispatchQueue.main.async { image = result }
                }
        }
        .onDisappear {
            if request != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(request)
                request = PHInvalidImageRequestID
            }
            image = nil
        }
    }
}

struct MediaDetailsPage: View {
    let itemID: String
    let fallback: LibraryMedia
    @ObservedObject var store: LibraryMediaStore
    let requestDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    private var item: LibraryMedia {
        store.media.first(where: { $0.id == itemID }) ?? fallback
    }

    var body: some View {
        List {
            Section("Preview") {
                if item.video {
                    if let player {
                        VideoPlayer(player: player).frame(height: 245)
                    } else {
                        MediaThumbnail(identifier: item.id, video: true).frame(height: 220)
                    }
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                } else {
                    MediaThumbnail(identifier: item.id, video: false).frame(height: 220)
                }
            }
            Section("Information") {
                LabeledContent("Name", value: item.filename)
                LabeledContent("Type", value: item.video ? "Video" : "Photo")
                LabeledContent(item.isEstimated ? "Photos resource size" : "Verified primary size",
                               value: item.byteCount.map(readable) ?? "Unknown")
                LabeledContent("Date", value: dateString(item.created))
                if item.video {
                    LabeledContent("Duration", value: String(format: "%.1f sec", item.duration))
                }
                if let path = item.verifiedPath {
                    Text(path).font(.footnote).textSelection(.enabled)
                } else {
                    Text("Filza path requires exact local-file verification. A matching photo or video preview is shown here regardless of file-path availability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Actions") {
                Button {
                    tryOpenSelectedInPhotos()
                } label: {
                    Label("Try Open This Item in Photos", systemImage: "photo.on.rectangle")
                }
                Text("Experimental: iOS 16 does not publicly guarantee deep linking to one Photos asset. The Photos app may open at the library instead.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                } label: { Label("Open Photos App", systemImage: "square.on.square") }
                if let path = item.verifiedPath {
                    FilzaAction(path: path, label: "Go to Exact File in Filza")
                } else {
                    Button {
                        store.inspect(item.id)
                    } label: {
                        Label(store.inspectingID == item.id ? "Verifying…" : "Verify Exact Size & Filza Path",
                              systemImage: "checkmark.shield")
                    }
                    .disabled(store.inspectingID != nil)
                    if store.inspectingID == item.id {
                        ProgressView()
                        Text("Reading this selected original only; may take time for large videos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    UIPasteboard.general.string = item.verifiedPath ?? item.filename
                } label: { Label("Copy File Name or Verified Path", systemImage: "doc.on.doc") }
                Button(role: .destructive, action: requestDelete) {
                    Label("Delete from Photos…", systemImage: "trash")
                }
            }
        }
        .navigationTitle(item.video ? "Video Details" : "Photo Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { preview() }
        .onDisappear {
            player?.pause()
            player = nil
            image = nil
        }
    }

    private func tryOpenSelectedInPhotos() {
        // Private iOS 16 routing is best-effort. Exact-item selection may fail.
        let token = String(itemID.split(separator: "/").first ?? "")
        guard let uuid = UUID(uuidString: token),
              let route = URL(string: "photos-navigation://asset?uuid=" + uuid.uuidString) else {
            if let library = URL(string: "photos-redirect://") {
                UIApplication.shared.open(library)
            }
            return
        }
        UIApplication.shared.open(route, options: [:]) { opened in
            if !opened, let library = URL(string: "photos-redirect://") {
                UIApplication.shared.open(library)
            }
        }
    }

    private func preview() {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [itemID], options: nil).firstObject else { return }
        if item.video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { video, _ in
                DispatchQueue.main.async {
                    if let video { self.player = AVPlayer(playerItem: video) }
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(for: asset,
                    targetSize: CGSize(width: 960, height: 960),
                    contentMode: .aspectFit, options: options) { result, _ in
                DispatchQueue.main.async {
                    if let result { self.image = result }
                }
            }
        }
    }
}
