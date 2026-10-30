import SwiftUI

/// Built into the Movies screen. Converts locally and preserves the originals.
/// Prepared outputs are cached in Movies, accessible in Files and shareable.
struct VideoConverterScreen: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var cast: CastController
    @StateObject private var preparer = MKVCastPreparer()
    @State private var selected: Movie?
    @State private var ready: Movie?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fast TV Converter", systemImage: "arrow.triangle.2.circlepath.video")
                            .font(.title2.bold()).foregroundStyle(.cyan)
                        Text("Prepare MP4, M4V or MOV files with stereo AAC audio using the iPhone native converter.")
                            .font(.subheadline)
                        Text("Fast mode copies video without re-encoding, so it avoids unnecessary quality loss. Conversion time depends on the original file and storage speed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.nextSurface()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("SOURCE VIDEO").font(.caption.bold()).foregroundStyle(.secondary)
                        if library.movies.isEmpty {
                            Text("Import a video from the Movies screen first.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Menu {
                                ForEach(library.movies) { movie in
                                    Button(movie.name) {
                                        selected = movie
                                        ready = nil
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "film.stack")
                                    Text(selected?.name ?? "Choose a movie").lineLimit(2)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                }
                                .padding(14)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(preparer.preparing)
                            if let selected {
                                Text("\(selected.format) · \(selected.fileSizeLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            guard let movie = selected else { return }
                            ready = nil
                            preparer.prepare(movie, library: library, forceConversion: true) { output in
                                ready = output
                            }
                        } label: {
                            Label(preparer.preparing ? "Preparing video…" : "Convert to TV MP4 + AAC",
                                  systemImage: "wand.and.stars")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).tint(.cyan)
                        .foregroundStyle(.black)
                        .disabled(preparer.preparing || selected == nil || selected?.isConverted == true)
                    }.nextSurface()

                    if preparer.preparing {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Conversion progress").font(.headline)
                                Spacer()
                                if preparer.hasTimeline {
                                    Text(String(format: "%.1f%%", preparer.progressFraction * 100))
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                            if preparer.hasTimeline {
                                ProgressView(value: preparer.progressFraction, total: 1).tint(.cyan)
                            } else {
                                ProgressView().tint(.cyan)
                            }
                            Text(preparer.status).font(.subheadline)
                            HStack {
                                Text("Elapsed: \(preparer.elapsedSeconds)s")
                                Spacer()
                                if let eta = preparer.estimatedRemainingSeconds {
                                    Text("Est. left: \(eta / 60)m \(eta % 60)s")
                                } else {
                                    Text(preparer.isFinalizing ? "Finalizing" : "Calculating ETA")
                                }
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("Processed: " + ByteCountFormatter.string(
                                fromByteCount: preparer.bytesProcessed, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Keep Next Cast open. Conversion runs locally and requires free space for an additional MP4.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Cancel preparation", role: .destructive) { preparer.cancel() }
                                .font(.subheadline)
                        }.nextSurface()
                    }

                    if let ready {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("TV MP4 ready", systemImage: "checkmark.circle.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(ready.fileSizeLabel).font(.caption).foregroundStyle(.secondary)
                            Text("Saved permanently under Movies → Converted. Reuse it any time without converting again.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button {
                                cast.load(ready)
                            } label: {
                                Label("Cast prepared MP4", systemImage: "tv")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!cast.isConnected)
                            if !cast.isConnected {
                                Text("Connect a Chromecast receiver before casting.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ShareLink(item: ready.localURL) {
                                Label("Export MP4 to Files or another app", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }.nextSurface()
                    }

                    Text("This crash-safe converter uses Apple AVFoundation only. It copies compatible H.264 video and converts supported soundtracks to stereo AAC. MKV/AVI conversion is disabled until a stable engine is available; local VLC playback still works.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }
            .navigationTitle("Video Converter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(preparer.preparing)
                }
            }
            .onAppear {
                if selected == nil { selected = library.movies.first }
            }
            .alert("Video Converter", isPresented: Binding(
                get: { preparer.errorMessage != nil },
                set: { if !$0 { preparer.errorMessage = nil } }
            )) {
                Button("OK") { preparer.errorMessage = nil }
            } message: {
                Text(preparer.errorMessage ?? "")
            }
        }
    }
}
