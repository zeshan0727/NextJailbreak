import SwiftUI
import Foundation
import Combine

/// Download direct media links only. Streaming pages/DRM/HLS need a separate
/// compatible downloader and are intentionally not misrepresented as movies.
@MainActor
final class VideoDownloads: ObservableObject {
    @Published var urlText = ""
    @Published var status = "Paste a direct video URL to begin."
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var lastCompleted: String?
    @Published var errorMessage: String?
    private var active: URLSessionDownloadTask?

    func refresh() {
        if let active {
            let fraction = active.progress.fractionCompleted
            if fraction.isFinite { progress = max(0, min(1, fraction)) }
        }
    }
    func cancel() {
        active?.cancel()
        active = nil
        isDownloading = false
        status = "Download cancelled"
    }
    func download(to library: MovieLibrary) {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = URL(string: raw),
              let scheme = link.scheme?.lowercased(), ["https", "http"].contains(scheme),
              link.host != nil else {
            errorMessage = "Enter a direct HTTP or HTTPS video file address."
            return
        }
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0
        status = "Connecting…"
        errorMessage = nil
        let request = URLRequest(url: link, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 45)
        let task = URLSession.shared.downloadTask(with: request) { [weak self] temporary, response, error in
            // A URLSession temporary file exists only for the lifetime of this callback.
            // Stage it synchronously before the callback returns.
            var staged: URL?
            var stagedError: Error? = error
            let suggested = response?.suggestedFilename ?? link.lastPathComponent
            let candidateName = URL(fileURLWithPath: suggested).lastPathComponent
            let ext = URL(fileURLWithPath: candidateName).pathExtension.lowercased()
            let mime = (response?.mimeType ?? "").lowercased()
            let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 200

            if httpCode < 200 || httpCode >= 300 {
                stagedError = NSError(domain: "NextCast", code: httpCode,
                    userInfo: [NSLocalizedDescriptionKey: "Server responded HTTP \(httpCode)."])
            } else if mime.contains("html") || mime.contains("json") || mime.contains("text/plain") {
                stagedError = NSError(domain: "NextCast", code: -4,
                    userInfo: [NSLocalizedDescriptionKey:
                        "This URL returned a webpage, not a downloadable movie. Paste a direct MP4/MKV/video file URL."])
            } else if !VideoFormats.extensions.contains(ext) {
                stagedError = NSError(domain: "NextCast", code: -5,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No supported video extension found in the download (\(candidateName)). Direct video URLs are required."])
            } else if let temporary, stagedError == nil {
                do {
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "." + ext)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    staged = destination
                } catch { stagedError = error }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.active = nil
                self.isDownloading = false
                if let stagedError {
                    self.status = "Download failed"
                    self.errorMessage = stagedError.localizedDescription
                    return
                }
                guard let staged else {
                    self.status = "Download failed"
                    self.errorMessage = "No file data was received."
                    return
                }
                do {
                    try library.addDownloadedFile(staged, suggestedName:
                        URL(fileURLWithPath: candidateName).deletingPathExtension().lastPathComponent)
                    self.progress = 1
                    self.status = "Saved to Movies"
                    self.lastCompleted = candidateName
                    self.urlText = ""
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.status = "Could not save the video"
                    try? FileManager.default.removeItem(at: staged)
                }
            }
        }
        active = task
        status = "Downloading video…"
        task.resume()
    }
}

struct DownloadsTab: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var downloads: VideoDownloads
    var openMovies: () -> Void
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Download a movie").font(.title2.bold())
                        Text("Paste a direct link to a video file. Saved videos automatically appear in Movies.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 13) {
                        TextField("https://example.com/movie.mp4", text: $downloads.urlText, axis: .vertical)
                            .lineLimit(2...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .padding(12)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        HStack(spacing: 10) {
                            Button {
                                if let text = UIPasteboard.general.string {
                                    downloads.urlText = text
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                downloads.download(to: library)
                            } label: {
                                Label("Download", systemImage: "arrow.down.to.line")
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(downloads.isDownloading)
                        }
                    }.nextSurface()

                    if downloads.isDownloading {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                ProgressView()
                                Text(downloads.status).font(.subheadline.bold())
                                Spacer()
                                Text("\(Int(downloads.progress * 100))%")
                                    .font(.caption.monospacedDigit())
                            }
                            ProgressView(value: downloads.progress)
                            Button("Cancel download", role: .destructive) {
                                downloads.cancel()
                            }.font(.subheadline)
                        }.nextSurface()
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: downloads.lastCompleted == nil
                                  ? "arrow.down.circle" : "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(downloads.lastCompleted == nil ? .cyan : .green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(downloads.status).font(.subheadline.bold())
                                if let name = downloads.lastCompleted {
                                    Text(name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }.nextSurface()
                        if downloads.lastCompleted != nil {
                            Button("Open Movies") { openMovies() }
                                .buttonStyle(.borderedProminent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Supported downloads", systemImage: "info.circle")
                            .font(.subheadline.bold())
                        Text("MP4, MKV, MOV, AVI, WEBM, FLV, WMV and other directly linked video files.")
                        Text("Web pages, DRM-protected streams, HLS playlists (.m3u8), torrent/magnet links, and sites requiring authenticated playback cannot be downloaded by this direct-file downloader.")
                    }.font(.footnote).foregroundStyle(.secondary).nextSurface()
                }.padding(18)
            }
            .navigationTitle("Downloads")
            .onReceive(timer) { _ in downloads.refresh() }
            .alert("Download", isPresented: Binding(
                get: { downloads.errorMessage != nil },
                set: { if !$0 { downloads.errorMessage = nil } }
            )) {
                Button("OK") { downloads.errorMessage = nil }
            } message: {
                Text(downloads.errorMessage ?? "")
            }
        }
    }
}
