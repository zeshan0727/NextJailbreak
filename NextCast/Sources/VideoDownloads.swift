import SwiftUI
import Foundation
import Combine

@MainActor
final class VideoDownloads: ObservableObject {
    @Published var urlText = ""
    @Published var errorMessage: String?

    func submit() {
        let value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            errorMessage = "Paste a valid direct HTTP/HTTPS video link."
            return
        }
        TransferStore.shared.start(URLRequest(url: url), origin: "Direct")
        urlText = ""
    }
}

struct DownloadsTab: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var downloads: VideoDownloads
    @ObservedObject var browserDownloads: BrowserDownloadStore
    @ObservedObject var transfers: TransferStore
    var openMovies: () -> Void
    @State private var refreshItem: DownloadRecord?
    @State private var newLinkText = ""
    @AppStorage("nextcast.preferBackgroundDownloads") private var preferBackgroundDownloads = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download Manager").font(.title2.bold())
                        Text("Reliable movie downloads · live MB/s · estimated time remaining")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 13) {
                        TextField("Paste a direct video URL", text: $downloads.urlText, axis: .vertical)
                            .lineLimit(2...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(11)
                            .background(.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12))
                        HStack(spacing: 10) {
                            Button {
                                if let text = UIPasteboard.general.string {
                                    downloads.urlText = text
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                downloads.submit()
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }.nextSurface()

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Download method", systemImage: "externaldrive.fill.badge.checkmark")
                            .font(.subheadline.bold()).foregroundStyle(.cyan)
                        Toggle(isOn: $preferBackgroundDownloads) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Use iOS background downloading")
                                    .font(.subheadline.bold())
                                Text(preferBackgroundDownloads
                                    ? "Optional: runs when switching apps, but iOS temporary-file access can fail on some devices."
                                    : "Recommended: saves directly to Movies from the first byte. Keep Next Cast open until complete.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.cyan)
                        Text("The selected method applies to new direct links and browser downloads. Reliable mode prevents a full transfer from being lost to a temporary-file permission failure. Background mode can use up to 3 server-approved connections.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.nextSurface()

                    HStack {
                        Text("Transfers").font(.title3.bold())
                        Spacer()
                        if !transfers.items.isEmpty {
                            Text("\(transfers.items.filter(\.isActive).count) active")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if transfers.items.isEmpty {
                        Text("No downloads yet. Paste a direct file URL above, or start a download in Browser.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).nextSurface()
                    }
                    ForEach(transfers.items) { item in
                        transferCard(item)
                    }

                    if !browserDownloads.items.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("Website-native Downloads").font(.title3.bold())
                            Text("Some browser-generated files cannot be handed to the background manager. These use WebKit's own downloader.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(browserDownloads.items) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.name).font(.subheadline.bold()).lineLimit(2)
                                    Text(item.status).font(.caption).foregroundStyle(.secondary)
                                    if item.status == "Downloading" {
                                        ProgressView(value: item.progress)
                                        HStack {
                                            Text(browserDownloads.speedLabel(item))
                                            Spacer()
                                            Text(browserDownloads.remainingLabel(item))
                                        }.font(.caption.monospacedDigit())
                                        Button("Cancel", role: .destructive) {
                                            browserDownloads.cancel(item)
                                        }.font(.caption)
                                    } else {
                                        HStack(spacing: 10) {
                                            if let file = browserDownloads.fileURL(item) {
                                                Button {
                                                    browserDownloads.moveToMovies(item, library: library)
                                                } label: {
                                                    Label("Move to Movies", systemImage: "film")
                                                }
                                                ShareLink(item: file) {
                                                    Label("Share", systemImage: "square.and.arrow.up")
                                                }
                                            }
                                            Spacer()
                                            Button("Clear", role: .destructive) {
                                                browserDownloads.delete(item)
                                            }
                                        }.font(.caption)
                                    }
                                }.nextSurface()
                            }
                        }
                    }
                    Text("Reliable mode writes directly to Movies and requires keeping Next Cast open. Background mode is optional and may fail at finalization on some phones. File access and available storage are checked before downloading in reliable mode. Protected streams are not supported.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 10)
                }.padding(18)
            }
            .navigationTitle("Downloads")
            .sheet(item: $refreshItem) { item in
                NavigationStack {
                    Form {
                        Section("Replace a stalled or expired download link") {
                            Text(item.name).font(.headline)
                            TextField("New direct video link", text: $newLinkText, axis: .vertical)
                                .lineLimit(3...6)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            Button("Paste from Clipboard") {
                                if let text = UIPasteboard.general.string { newLinkText = text }
                            }
                        }
                        Section {
                            Button("Apply Link and Restart") {
                                transfers.retry(item.id, replacementURL: newLinkText)
                                refreshItem = nil
                            }
                            .disabled(newLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } footer: {
                            Text("Replacing a download URL restarts this transfer safely from zero, to avoid mixing parts from different versions of a file. Pause/Resume preserves downloaded bytes while iOS retains the existing session.")
                        }
                    }
                    .navigationTitle("Refresh Link")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancel") { refreshItem = nil }
                        }
                    }
                }
            }
            .onAppear { transfers.attach(library); transfers.refresh() }
            .onReceive(timer) { _ in
                transfers.refresh()
                browserDownloads.tick()
            }
            .alert("Download Manager", isPresented: Binding(
                get: { downloads.errorMessage != nil || transfers.error != nil || browserDownloads.notice != nil },
                set: {
                    if !$0 {
                        downloads.errorMessage = nil
                        transfers.error = nil
                        browserDownloads.notice = nil
                    }
                }
            )) {
                Button("OK") {
                    downloads.errorMessage = nil
                    transfers.error = nil
                    browserDownloads.notice = nil
                }
            } message: {
                Text(downloads.errorMessage ?? transfers.error ?? browserDownloads.notice ?? "")
            }
        }
    }

    private func transferCard(_ item: DownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: item.isActive ? "arrow.down.circle.fill" :
                        item.status.contains("Movies") ? "checkmark.circle.fill" : "doc.fill")
                    .font(.title2).foregroundStyle(item.isActive ? .cyan : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.subheadline.bold()).lineLimit(2)
                    Text(item.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if item.isActive { ProgressView().tint(.cyan) }
            }
            if item.isActive || item.isPaused {
                if item.expected > 0 {
                    ProgressView(value: item.fraction).tint(.cyan)
                } else {
                    ProgressView().tint(.cyan)
                }
                HStack {
                    Text("\(size(item.received)) / \(item.expected > 0 ? size(item.expected) : "Unknown")")
                    Spacer()
                    Text(item.expected > 0 ? "\(Int(item.fraction * 100))%" : "—")
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)

                HStack {
                    Label(speed(item.speed), systemImage: "speedometer")
                    Spacer()
                    Label(eta(item.remaining), systemImage: "clock")
                }.font(.caption.bold()).foregroundStyle(.cyan)
                HStack {
                    Text(item.mode).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if item.isPaused {
                        Button {
                            transfers.resume(item.id)
                        } label: { Label("Resume", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent)
                    } else if item.status != "Finalizing" {
                        Button {
                            transfers.pause(item.id)
                        } label: { Label("Pause", systemImage: "pause.fill") }
                            .buttonStyle(.bordered)
                    }
                    Button("Stop", role: .destructive) { transfers.cancel(item.id) }
                        .font(.caption)
                }
                HStack {
                    Button {
                        transfers.retry(item.id)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    Button {
                        transfers.startSafeStream(item.id)
                    } label: {
                        Label("Safe Download", systemImage: "shield.lefthalf.filled")
                    }
                    Button {
                        newLinkText = item.url
                        refreshItem = item
                    } label: {
                        Label("Refresh Link", systemImage: "link")
                    }
                    Spacer()
                }.font(.caption).buttonStyle(.bordered)
            } else {
                HStack {
                    Text(item.origin).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if item.status == "Added to Movies" {
                        Button("Open Movies") { openMovies() }.font(.caption.bold())
                    } else if let path = item.savedPath {
                        Button {
                            transfers.moveToMovies(item.id, library: library)
                        } label: {
                            Label("Move to Movies", systemImage: "film")
                        }.font(.caption)
                        ShareLink(item: URL(fileURLWithPath: path)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }.font(.caption)
                    }
                    Button("Clear", role: .destructive) { transfers.delete(item.id) }
                        .font(.caption)
                }
                if item.canRetry {
                    HStack {
                        Button {
                            transfers.retry(item.id)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        Button {
                            transfers.startSafeStream(item.id)
                        } label: {
                            Label("Safe Download", systemImage: "shield.lefthalf.filled")
                        }
                        Button {
                            newLinkText = item.url
                            refreshItem = item
                        } label: {
                            Label("Refresh Link", systemImage: "link")
                        }
                        Spacer()
                    }.font(.caption).buttonStyle(.bordered)
                }
            }
        }.nextSurface()
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
    private func speed(_ bytes: Double) -> String {
        guard bytes > 0 else { return "Calculating speed" }
        return String(format: "%.2f MB/s", bytes / 1_000_000)
    }
    private func eta(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "ETA calculating" }
        let t = Int(max(0, seconds))
        if t >= 3600 { return String(format: "%dh %02dm", t/3600, (t%3600)/60) }
        if t >= 60 { return String(format: "%dm %02ds", t/60, t%60) }
        return "\(t)s remaining"
    }
}
