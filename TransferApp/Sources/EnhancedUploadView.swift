import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private let enhancedUploadRepo = "zeshan0727/NextJailbreak"

enum EnhancedPickerDestination: String, Identifiable {
    case files
    case photos
    case videos

    var id: String { rawValue }
}

enum EnhancedPhotoMediaKind {
    case photo
    case video

    var filter: PHPickerFilter {
        switch self {
        case .photo:
            return .images
        case .video:
            return .videos
        }
    }

    var preferredIdentifier: String {
        switch self {
        case .photo:
            return UTType.image.identifier
        case .video:
            return UTType.movie.identifier
        }
    }

    var fallbackName: String {
        switch self {
        case .photo:
            return "photo"
        case .video:
            return "video"
        }
    }
}

struct EnhancedPhotoLibraryPicker: UIViewControllerRepresentable {
    let kind: EnhancedPhotoMediaKind
    let onPick: (URL) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            kind: kind,
            onPick: onPick,
            onCancel: onCancel,
            onFailure: onFailure
        )
    }

    func makeUIViewController(
        context: Context
    ) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = kind.filter
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: PHPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let kind: EnhancedPhotoMediaKind
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        let onFailure: (String) -> Void

        init(
            kind: EnhancedPhotoMediaKind,
            onPick: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.kind = kind
            self.onPick = onPick
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            guard let provider = results.first?.itemProvider else {
                onCancel()
                return
            }

            let identifier: String

            if provider.hasItemConformingToTypeIdentifier(kind.preferredIdentifier) {
                identifier = kind.preferredIdentifier
            } else if kind == .video,
                      provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
                identifier = UTType.video.identifier
            } else {
                DispatchQueue.main.async {
                    self.onFailure("The selected Photos item could not be read.")
                }
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: identifier) { sourceURL, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onFailure("Photos picker failed: \(error.localizedDescription)")
                    }
                    return
                }

                guard let sourceURL else {
                    DispatchQueue.main.async {
                        self.onFailure("Photos did not return a usable file.")
                    }
                    return
                }

                do {
                    let localURL = try Self.copyIntoUploadCache(
                        sourceURL: sourceURL,
                        suggestedName: provider.suggestedName,
                        fallbackName: self.kind.fallbackName
                    )

                    DispatchQueue.main.async {
                        self.onPick(localURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onFailure("Could not prepare selected media: \(error.localizedDescription)")
                    }
                }
            }
        }

        private static func copyIntoUploadCache(
            sourceURL: URL,
            suggestedName: String?,
            fallbackName: String
        ) throws -> URL {
            let directory = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PickedMedia", isDirectory: true)

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            var name = suggestedName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if name.isEmpty {
                name = fallbackName
            }

            name = name
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: ":", with: "_")

            if URL(fileURLWithPath: name).pathExtension.isEmpty,
               !sourceURL.pathExtension.isEmpty {
                name += ".\(sourceURL.pathExtension)"
            }

            let destination = directory
                .appendingPathComponent("\(UUID().uuidString)-\(name)")

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }
}

struct EnhancedUploadView: View {
    @State private var activePicker: EnhancedPickerDestination?
    @State private var selectedURL: URL?
    @State private var isUploading = false
    @State private var resultText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                TransferGlassBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        uploadHeader
                        sourcePickerCard

                        if let selectedURL {
                            selectedFileCard(selectedURL)
                        }

                        connectionCard

                        if !resultText.isEmpty {
                            resultCard
                        }

                        Text("Files are uploaded to transfer/uploads/")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.27))
                            .padding(.top, 2)
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $activePicker) { destination in
                pickerSheet(destination)
            }
        }
    }

    private var uploadHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Upload")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Phone → NS Transfers")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.60))
            }

            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var sourcePickerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Source")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Pick a normal file, photo, or video from iOS.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }

            HStack(spacing: 10) {
                sourceButton(
                    title: "Files",
                    systemName: "folder.fill.badge.plus",
                    destination: .files
                )

                sourceButton(
                    title: "Photos",
                    systemName: "photo.on.rectangle.angled",
                    destination: .photos
                )

                sourceButton(
                    title: "Videos",
                    systemName: "video.badge.plus",
                    destination: .videos
                )
            }
        }
        .padding(16)
        .transferGlassPanel(cornerRadius: 22)
    }

    private func sourceButton(
        title: String,
        systemName: String,
        destination: EnhancedPickerDestination
    ) -> some View {
        Button {
            activePicker = destination
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.09))

                    Image(systemName: systemName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .frame(width: 45, height: 45)

                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.10),
                                .white.opacity(0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedFileCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.09))

                    Image(systemName: selectedIcon(for: url))
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let size = fileSizeDescription(url) {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }

                Spacer()
            }

            HStack(spacing: 9) {
                Button {
                    Task {
                        await uploadToGitHub(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.78)
                        } else {
                            Image(systemName: "icloud.and.arrow.up.fill")
                        }

                        Text(isUploading ? "Uploading…" : "Upload Selected")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(
                        Capsule()
                            .fill(TransferTheme.actionGradient)
                    )
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.22), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUploading)

                Button(role: .destructive) {
                    selectedURL = nil
                    resultText = "Selected file removed."
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash")
                        Text("Remove")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color.red.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.red.opacity(0.18), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
            }
        }
        .padding(16)
        .transferGlassPanel(cornerRadius: 22)
    }

    private var connectionCard: some View {
        let configured = !SecureTokenStore.load().isEmpty

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        configured
                            ? Color.green.opacity(0.13)
                            : Color.orange.opacity(0.13)
                    )

                Image(systemName: configured ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        configured
                            ? Color.green.opacity(0.90)
                            : Color.orange.opacity(0.90)
                    )
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(configured ? "GitHub Connected" : "GitHub Token Required")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                Text(
                    configured
                        ? "Ready to upload to NextJailbreak."
                        : "Configure the token once in Settings."
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()
        }
        .padding(16)
        .transferGlassPanel(cornerRadius: 22)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Last Result", systemImage: "terminal.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Text(resultText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .transferGlassPanel(cornerRadius: 22)
    }

    @ViewBuilder
    private func pickerSheet(
        _ destination: EnhancedPickerDestination
    ) -> some View {
        switch destination {
        case .files:
            DocumentPicker(
                onPick: { url in
                    selectedURL = url
                    resultText = "Selected from Files: \(url.lastPathComponent)"
                    activePicker = nil
                },
                onCancel: {
                    activePicker = nil
                }
            )
            .ignoresSafeArea()

        case .photos:
            EnhancedPhotoLibraryPicker(
                kind: .photo,
                onPick: { url in
                    selectedURL = url
                    resultText = "Selected photo: \(url.lastPathComponent)"
                    activePicker = nil
                },
                onCancel: {
                    activePicker = nil
                },
                onFailure: { message in
                    resultText = message
                    activePicker = nil
                }
            )
            .ignoresSafeArea()

        case .videos:
            EnhancedPhotoLibraryPicker(
                kind: .video,
                onPick: { url in
                    selectedURL = url
                    resultText = "Selected video: \(url.lastPathComponent)"
                    activePicker = nil
                },
                onCancel: {
                    activePicker = nil
                },
                onFailure: { message in
                    resultText = message
                    activePicker = nil
                }
            )
            .ignoresSafeArea()
        }
    }

    private func uploadToGitHub(_ url: URL) async {
        let token = SecureTokenStore.load()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            resultText = "GitHub upload token is not configured. Open Settings first."
            return
        }

        isUploading = true
        defer { isUploading = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            guard data.count <= 40 * 1024 * 1024 else {
                resultText = "Selected item is larger than the current 40 MB direct-upload limit."
                return
            }

            let safeName = sanitize(url.lastPathComponent)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let path = "transfer/uploads/\(formatter.string(from: Date()))-\(safeName)"

            let encodedPath = path
                .split(separator: "/")
                .map { component -> String in
                    let value = String(component)
                    return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
                }
                .joined(separator: "/")

            guard let apiURL = URL(
                string: "https://api.github.com/repos/\(enhancedUploadRepo)/contents/\(encodedPath)"
            ) else {
                throw URLError(.badURL)
            }

            let payload: [String: Any] = [
                "message": "Upload \(safeName) from NS Transfers",
                "content": data.base64EncodedString(),
                "branch": "main"
            ]

            var request = URLRequest(url: apiURL)
            request.httpMethod = "PUT"
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = 180
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("NS-Transfers", forHTTPHeaderField: "User-Agent")

            let (responseData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if (200...299).contains(status) {
                resultText = "Uploaded successfully.\n\nPath: \(path)\n\nSend this path in ChatGPT so the file can be retrieved from the repo."
                selectedURL = nil
            } else {
                let message = (
                    try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                )?["message"] as? String

                resultText = "GitHub returned HTTP \(status): \(message ?? "Unknown error")"
            }
        } catch {
            resultText = "Upload failed: \(error.localizedDescription)"
        }
    }

    private func selectedIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) {
                return "photo.fill"
            }

            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return "video.fill"
            }

            if type.conforms(to: .archive) {
                return "archivebox.fill"
            }
        }

        return "doc.fill"
    }

    private func fileSizeDescription(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }

        return ByteCountFormatter.string(
            fromByteCount: Int64(size),
            countStyle: .file
        )
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))

        return name.unicodeScalars
            .map { allowed.contains($0) ? Character(String($0)) : "_" }
            .reduce("") { $0 + String($1) }
    }
}
