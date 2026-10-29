import SwiftUI
import Photos
import AVKit
import CryptoKit
import UIKit

// Native Photos owns library deletion. Directly unlinking DCIM files would corrupt
// the Photos database; the app never performs filesystem deletion of photo assets.
struct LibraryMedia: Identifiable {
    let asset: PHAsset
    let filename: String
    let resource: PHAssetResource?
    let created: Date?
    let video: Bool
    var byteCount: Int64?
    var checked = false
    var physicalPath: String? = nil
    var id: String { asset.localIdentifier }
    var duration: Double { asset.duration }
}

private struct PhysicalCandidate {
    let url: URL
    let bytes: Int64
}

private final class MediaScanControl {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

private enum PhotosMeasure {
    static func selectedResource(_ asset: PHAsset) -> PHAssetResource? {
        let all = PHAssetResource.assetResources(for: asset)
        let order: [PHAssetResourceType] = asset.mediaType == .video
          ? [.fullSizeVideo, .video]
          : [.fullSizePhoto, .photo]
        for type in order {
            if let result = all.first(where: { $0.type == type }) { return result }
        }
        return nil
    }

    // The only public, accurate way to size an individual PHAssetResource
    // without reading undocumented metadata is PHAssetResourceManager.requestData.
    // Network is disabled: iCloud-only originals are marked unavailable.
    static func lengthAndHash(_ resource: PHAssetResource, hash: Bool, control: MediaScanControl)
      -> (Int64, String)? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let gate = DispatchSemaphore(value: 0)
        let guardLock = NSLock()
        var length: Int64 = 0
        var digest = SHA256()
        var success = false
        let request = PHAssetResourceManager.default().requestData(
            for: resource,
            options: options,
            dataReceivedHandler: { data in
                guardLock.lock()
                length += Int64(data.count)
                if hash { digest.update(data: data) }
                guardLock.unlock()
            }, completionHandler: { error in
                guardLock.lock()
                success = (error == nil)
                guardLock.unlock()
                gate.signal()
            }
        )
        let completed = gate.wait(timeout: .now() + 70) == .success
        if !completed || control.cancelled {
            PHAssetResourceManager.default().cancelDataRequest(request)
            return nil
        }
        guardLock.lock()
        defer { guardLock.unlock() }
        return success ? (length, hash ? digest.finalize().map { String(format: "%02x", $0) }.joined() : "") : nil
    }

    private static func shaFile(_ url: URL, control: MediaScanControl) -> String? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var digest = SHA256()
        while !control.cancelled {
            guard let chunk = try? file.read(upToCount: 1_048_576) else { return nil }
            if chunk.isEmpty {
                return digest.finalize().map { String(format: "%02x", $0) }.joined()
            }
            digest.update(data: chunk)
        }
        return nil
    }

    static func findDCIMFiles(control: MediaScanControl) -> [String: [PhysicalCandidate]] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/private/var/mobile/Media/DCIM", isDirectory: true)
        guard let enumerator = fm.enumerator(at: root,
              includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [:] }
        var found = [String: [PhysicalCandidate]]()
        while let url = enumerator.nextObject() as? URL {
            if control.cancelled { break }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize else { continue }
            let key = url.lastPathComponent.lowercased()
            found[key, default: []].append(PhysicalCandidate(url: url, bytes: Int64(size)))
        }
        return found
    }

    // A path is considered exact only if its original filename, logical byte
    // count AND cryptographic content digest all agree with a unique DCIM file.
    static func verifiedPath(resource: PHAssetResource,
                             bytes: Int64,
                             resourceDigest: String,
                             files: [String: [PhysicalCandidate]],
                             control: MediaScanControl) -> String? {
        let candidates = (files[resource.originalFilename.lowercased()] ?? [])
            .filter { $0.bytes == bytes }
        guard !candidates.isEmpty else { return nil }
        var matches = [String]()
        for candidate in candidates {
            if control.cancelled { return nil }
            if shaFile(candidate.url, control: control) == resourceDigest {
                matches.append(candidate.url.path)
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

@MainActor
final class LibraryMediaStore: ObservableObject {
    @Published private(set) var media = [LibraryMedia]()
    @Published private(set) var permission: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var running = false
    @Published private(set) var finished = false
    @Published private(set) var done = 0
    @Published private(set) var unknown = 0
    @Published private(set) var status = ""
    @Published var alertError: String?
    private var control: MediaScanControl?
    private var runID = UUID()

    var measuredSize: Int64 { media.compactMap(\.byteCount).reduce(0, +) }
    var isAllowed: Bool { permission == .authorized || permission == .limited }

    func requestAndScan() {
        permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if isAllowed { scan(); return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] value in
            Task { @MainActor [weak self] in
                self?.permission = value
                if self?.isAllowed == true { self?.scan() }
            }
        }
    }

    func cancel() {
        control?.cancel()
        runID = UUID()
        running = false
        status = "Scan interrupted; sizes may be incomplete"
    }

    func scan() {
        guard isAllowed, !running else { return }
        running = true
        finished = false
        done = 0
        unknown = 0
        media = []
        status = "Listing Photos library…"
        let token = MediaScanControl()
        let current = UUID()
        control = token
        runID = current

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fetch = PHAsset.fetchAssets(with: nil)
            var items = [LibraryMedia]()
            items.reserveCapacity(fetch.count)
            fetch.enumerateObjects { asset, _, _ in
                guard asset.mediaType == .image || asset.mediaType == .video else { return }
                let resource = PhotosMeasure.selectedResource(asset)
                let name = resource?.originalFilename ?? (asset.mediaType == .video ? "Video" : "Photo")
                items.append(LibraryMedia(asset: asset, filename: name, resource: resource,
                                          created: asset.creationDate, video: asset.mediaType == .video))
            }
            if token.cancelled { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.runID == current else { return }
                self.media = items
                self.status = "Matching on-device media files…"
            }
            let dcim = PhotosMeasure.findDCIMFiles(control: token)
            if token.cancelled { return }
            let count = items.count
            var pending = [(Int, LibraryMedia)]()
            for index in items.indices {
                if token.cancelled { return }
                var item = items[index]
                if let resource = item.resource {
                    let hasCandidate = dcim[resource.originalFilename.lowercased()] != nil
                    if let size = PhotosMeasure.lengthAndHash(resource, hash: hasCandidate, control: token) {
                        item.byteCount = size.0
                        if hasCandidate {
                            item.physicalPath = PhotosMeasure.verifiedPath(
                                resource: resource, bytes: size.0, resourceDigest: size.1,
                                files: dcim, control: token)
                        }
                    }
                }
                item.checked = true
                items[index] = item
                pending.append((index, item))
                if pending.count >= 12 || index == count - 1 {
                    let updates = pending
                    pending.removeAll(keepingCapacity: true)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.runID == current else { return }
                        for (pos, value) in updates where pos < self.media.count {
                            self.media[pos] = value
                        }
                        self.done = index + 1
                        self.unknown = self.media.filter { $0.checked && $0.byteCount == nil }.count
                        self.status = "Analyzed \(self.done) / \(count) media files"
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.runID == current else { return }
                self.running = false
                self.finished = true
                self.status = "Completed. Cloud-only or restricted originals may show unavailable sizes."
                self.control = nil
            }
        }
    }

    func delete(_ item: LibraryMedia) {
        guard isAllowed else { alertError = "Photos access is not granted."; return }
        // iOS displays its own second confirmation and moves to Recently Deleted.
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([item.asset] as NSArray)
        }, completionHandler: { [weak self] ok, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.media.removeAll { $0.id == item.id }
                } else {
                    self.alertError = error?.localizedDescription ?? "Photos could not delete the item."
                }
            }
        })
    }
}

private enum MediaViewFilter: String, CaseIterable {
    case all = "All", photos = "Photos", videos = "Videos"
}
private enum MediaOrder: String, CaseIterable {
    case largest = "Largest", smallest = "Smallest", newest = "Newest", oldest = "Oldest", name = "Filename"
}

struct PhotosStoragePage: View {
    @StateObject private var store = LibraryMediaStore()
    @State private var filter = MediaViewFilter.all
    @State private var order = MediaOrder.largest
    @State private var query = ""
    @State private var selected: LibraryMedia?
    @State private var deleting: LibraryMedia?
    @State private var showingError = false

    private var displayed: [LibraryMedia] {
        let source = store.media.filter { item in
            let kind = filter == .all || (filter == .videos && item.video) || (filter == .photos && !item.video)
            return kind && (query.isEmpty || item.filename.localizedCaseInsensitiveContains(query))
        }
        switch order {
        case .largest: return source.sorted { ($0.byteCount ?? -1) > ($1.byteCount ?? -1) }
        case .smallest: return source.sorted { ($0.byteCount ?? Int64.max) < ($1.byteCount ?? Int64.max) }
        case .newest: return source.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .oldest: return source.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
        case .name: return source.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Photos & Videos").font(.title2.bold())
                        Text("\(store.media.count) items in accessible Photos library")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundStyle(.mint)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Measured media").font(.caption).foregroundStyle(.secondary)
                        Text(readable(store.measuredSize)).font(.title3.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Scanned").font(.caption).foregroundStyle(.secondary)
                        Text("\(store.done)/\(store.media.count)").font(.title3.bold())
                    }
                }
                if store.permission == .limited {
                    Label("Limited Photos permission: only selected items are visible.", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("Counts primary photo/video resources, not all edits, Live Photo companions or APFS snapshots. Cloud-only originals are excluded unless locally available.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.running {
                    ProgressView(value: Double(store.done), total: Double(max(1, store.media.count))).tint(.mint)
                    Button("Stop Media Scan", role: .cancel) { store.cancel() }
                } else {
                    Button { store.requestAndScan() } label: {
                        Label(store.media.isEmpty ? "Scan Photos & Videos" : "Rescan Photos & Videos",
                              systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderedProminent)
                }
                if !store.status.isEmpty {
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
                if store.unknown > 0 {
                    Text("\(store.unknown) files have unavailable sizes (possibly iCloud or restricted).")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if store.isAllowed {
                Section {
                    Picker("Type", selection: $filter) {
                        ForEach(MediaViewFilter.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }.pickerStyle(.segmented)
                    Picker("Sort", selection: $order) {
                        ForEach(MediaOrder.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    HStack {
                        Text("\(displayed.count) shown").foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Text("\(store.media.filter { $0.physicalPath != nil }.count) Filza verified")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
                Section("Largest media files") {
                    ForEach(displayed) { item in
                        Button { selected = item } label: {
                            MediaListRow(item: item)
                        }.buttonStyle(.plain)
                        .contextMenu {
                            if let exact = item.physicalPath {
                                FilzaAction(path: exact, label: "Go to Exact File in Filza")
                            }
                            Button {
                                UIPasteboard.general.string = item.physicalPath ?? item.filename
                            } label: { Label("Copy File Name / Path", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { deleting = item } label: {
                                Label("Delete from Photos…", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("Grant Photos access to inspect your library. No upload is performed.")
                    if store.permission == .denied || store.permission == .restricted {
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
        .searchable(text: $query, prompt: "Search media filename")
        .sheet(item: $selected) { item in
            NavigationStack {
                MediaDetailsPage(item: item) { deleting = item; selected = nil }
            }
        }
        .confirmationDialog("Move this item to Recently Deleted?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete from Photos", role: .destructive) {
                if let item = deleting { store.delete(item) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("iOS will ask for confirmation. This uses the Photos library deletion API; it never directly removes DCIM files.")
        }
        .alert("Media Operation", isPresented: Binding(
            get: { store.alertError != nil },
            set: { if !$0 { store.alertError = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertError = nil }
        } message: { Text(store.alertError ?? "") }
    }
}

private struct MediaListRow: View {
    let item: LibraryMedia
    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnail(asset: item.asset)
                .frame(width: 70, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.filename).font(.subheadline.weight(.semibold))
                    .lineLimit(2).foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Image(systemName: item.video ? "video.fill" : "photo.fill")
                    Text(dateString(item.created))
                    if item.physicalPath != nil { Image(systemName: "folder.badge.checkmark") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.byteCount.map(readable) ?? (item.checked ? "Unavailable" : "Pending"))
                    .font(.caption).monospacedDigit().foregroundStyle(.primary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MediaThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var request: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            Color.gray.opacity(0.18)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: asset.mediaType == .video ? "film" : "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .onAppear {
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            request = PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 180, height: 180),
                contentMode: .aspectFill, options: options
            ) { result, _ in
                DispatchQueue.main.async { image = result }
            }
        }
        .onDisappear {
            if request != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(request) }
        }
    }
}

struct MediaDetailsPage: View {
    let item: LibraryMedia
    let requestDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var videoPlayer: AVPlayer?
    @State private var playbackError = false

    var body: some View {
        List {
            Section("Preview") {
                if item.video {
                    if let videoPlayer {
                        VideoPlayer(player: videoPlayer).frame(height: 280)
                    } else {
                        MediaThumbnail(asset: item.asset).frame(height: 230)
                        if playbackError {
                            Text("This video is not locally available for preview.")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                    }
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 350)
                } else {
                    MediaThumbnail(asset: item.asset).frame(height: 250)
                }
            }
            Section("File information") {
                LabeledContent("Name", value: item.filename)
                LabeledContent("Type", value: item.video ? "Video" : "Photo")
                LabeledContent("Main resource size", value: item.byteCount.map(readable) ?? "Unavailable")
                LabeledContent("Created", value: dateString(item.created))
                if item.video {
                    LabeledContent("Duration", value: String(format: "%.1f seconds", item.duration))
                }
                if let path = item.physicalPath {
                    Text(path).font(.caption2).textSelection(.enabled)
                } else {
                    Text("No verified local filesystem path. Photos hides its asset-to-file mapping; no Filza path is guessed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Actions") {
                if let path = item.physicalPath {
                    FilzaAction(path: path, label: "Go to Exact File in Filza")
                } else {
                    Label("Filza location unavailable", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
                Button {
                    UIPasteboard.general.string = item.physicalPath ?? item.filename
                } label: {
                    Label("Copy File Name / Path", systemImage: "doc.on.doc")
                }
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
        .onAppear { loadPreview() }
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer = nil
        }
    }

    private func loadPreview() {
        if item.video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { result, _ in
                DispatchQueue.main.async {
                    if let result { videoPlayer = AVPlayer(playerItem: result) }
                    else { playbackError = true }
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: item.asset,
                  targetSize: CGSize(width: 1400, height: 1400),
                  contentMode: .aspectFit, options: options) { result, _ in
                DispatchQueue.main.async {
                    if let result { image = result }
                }
            }
        }
    }
}
