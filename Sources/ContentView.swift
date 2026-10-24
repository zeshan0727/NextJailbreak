import SwiftUI
import PhotosUI
import Photos

final class PhotoCombinerViewModel: ObservableObject {
    @Published var selectedImages: [UIImage] = []
    @Published var combinedImage: UIImage? = nil
    @Published var showPhotoPicker = false
    @Published var showCombinedPhoto = false
    @Published var alertItem: AlertItem? = nil
    @Published var isSaving = false
    @Published var showSettingsAlert = false
    
    private let combinedImageFilename = "combined_photo.png"
    private var combinedImageURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(combinedImageFilename)
    }
    
    init() {
        loadCombinedImage()
    }
    
    func loadCombinedImage() {
        guard let url = combinedImageURL,
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            combinedImage = nil
            return
        }
        combinedImage = image
    }
    
    func saveCombinedImageToDisk(_ image: UIImage) {
        guard let url = combinedImageURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = image.pngData() {
                do {
                    try data.write(to: url, options: [.atomic])
                    DispatchQueue.main.async {
                        self.combinedImage = image
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.alertItem = AlertItem(title: "Save Error", message: "Failed to save combined image locally.", dismissButton: .default(Text("OK")))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.alertItem = AlertItem(title: "Save Error", message: "Failed to encode combined image.", dismissButton: .default(Text("OK")))
                }
            }
        }
    }
    
    func combineSelectedImages() {
        guard selectedImages.count >= 2 else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let combined = Self.combineImagesSideBySide(images: self.selectedImages) {
                DispatchQueue.main.async {
                    self.saveCombinedImageToDisk(combined)
                    self.showCombinedPhoto = true
                }
            } else {
                DispatchQueue.main.async {
                    self.alertItem = AlertItem(title: "Combine Error", message: "Failed to combine selected photos.", dismissButton: .default(Text("OK")))
                }
            }
        }
    }
    
    static func combineImagesSideBySide(images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else { return nil }
        // Uniform height: choose min height among images
        let targetHeight = images.map { $0.size.height }.min() ?? 0
        if targetHeight == 0 { return nil }
        
        // Resize images to uniform height, keep aspect ratio
        let resizedImages = images.compactMap { image -> UIImage? in
            let scale = targetHeight / image.size.height
            let newWidth = image.size.width * scale
            let newSize = CGSize(width: newWidth, height: targetHeight)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resized
        }
        
        let totalWidth = resizedImages.reduce(0) { $0 + $1.size.width }
        let finalSize = CGSize(width: totalWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(finalSize, false, 0)
        var xOffset: CGFloat = 0
        for img in resizedImages {
            img.draw(in: CGRect(x: xOffset, y: 0, width: img.size.width, height: img.size.height))
            xOffset += img.size.width
        }
        let combinedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return combinedImage
    }
    
    func saveCombinedImageToPhotoLibrary() {
        guard let image = combinedImage else { return }
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                self.isSaving = false
                switch status {
                case .authorized, .limited:
                    UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.saveCompletion(_:didFinishSavingWithError:contextInfo:)), nil)
                case .denied, .restricted, .notDetermined:
                    self.alertItem = AlertItem(
                        title: "Permission Denied",
                        message: "App does not have permission to save photos. Please enable access in Settings.",
                        primaryButton: .default(Text("Open Settings"), action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }),
                        secondaryButton: .cancel())
                @unknown default:
                    self.alertItem = AlertItem(title: "Error", message: "Unknown permission status.", dismissButton: .default(Text("OK")))
                }
            }
        }
    }
    
    @objc private func saveCompletion(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            alertItem = AlertItem(title: "Save Error", message: error.localizedDescription, dismissButton: .default(Text("OK")))
        } else {
            alertItem = AlertItem(title: "Saved", message: "Combined photo saved to your library.", dismissButton: .default(Text("OK")))
        }
    }
    
    func clearSelection() {
        selectedImages = []
    }
}

struct AlertItem: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var dismissButton: Alert.Button? = nil
    var primaryButton: Alert.Button? = nil
    var secondaryButton: Alert.Button? = nil
    
    var alert: Alert {
        if let primary = primaryButton, let secondary = secondaryButton {
            return Alert(title: Text(title), message: Text(message), primaryButton: primary, secondaryButton: secondary)
        } else {
            return Alert(title: Text(title), message: Text(message), dismissButton: dismissButton)
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = PhotoCombinerViewModel()
    
    var body: some View {
        NavigationStack {
            MainView()
                .environmentObject(vm)
                .navigationDestination(isPresented: $vm.showCombinedPhoto) {
                    if let combined = vm.combinedImage {
                        CombinedPhotoView(image: combined, count: vm.selectedImages.count)
                            .environmentObject(vm)
                    }
                }
                .alert(item: $vm.alertItem) { $0.alert }
                .sheet(isPresented: $vm.showPhotoPicker) {
                    PhotoPicker(selectedImages: $vm.selectedImages)
                }
                .navigationTitle("Select Photos")
        }
    }
}

private struct MainView: View {
    @EnvironmentObject private var vm: PhotoCombinerViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Button(action: { vm.showPhotoPicker = true }) {
                Text("Select Photos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(10)
            }
            .accessibilityLabel("Select photos button")
            
            if vm.selectedImages.isEmpty {
                Text("No photos selected.")
                    .foregroundColor(.secondary)
                    .font(.body)
                    .accessibilityLabel("No photos selected")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 10) {
                        ForEach(Array(vm.selectedImages.enumerated()), id: \ .offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                                .accessibilityLabel("Selected photo \(index + 1) of \(vm.selectedImages.count)")
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 100)
            }
            
            Button(action: vm.combineSelectedImages) {
                Text("Combine Photos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.selectedImages.count >= 2 ? Color.accentColor : Color.gray.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(vm.selectedImages.count < 2)
            .accessibilityLabel("Combine photos button")
            
            if vm.combinedImage != nil {
                Button(action: { vm.showCombinedPhoto = true }) {
                    Text("View Last Combined Photo")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
                .accessibilityLabel("View last combined photo button")
            }
            Spacer()
        }
        .padding()
    }
}

private struct CombinedPhotoView: View {
    @EnvironmentObject private var vm: PhotoCombinerViewModel
    let image: UIImage
    let count: Int
    @State private var isSharePresented = false
    
    var body: some View {
        VStack(spacing: 20) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Combined photo of \(count) images.")
                    .padding()
            }
            
            HStack(spacing: 20) {
                Button(action: vm.saveCombinedImageToPhotoLibrary) {
                    Label("Save to Library", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(10)
                }
                .accessibilityLabel("Save combined photo to library")
                .disabled(vm.isSaving)
                
                Button(action: { isSharePresented = true }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(10)
                }
                .accessibilityLabel("Share combined photo")
                .disabled(vm.isSaving)
            }
            
            Button("Back") {
                vm.showCombinedPhoto = false
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(10)
            .accessibilityLabel("Back to photo selection")
        }
        .padding()
        .navigationTitle("Combined Photo")
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(activityItems: [image])
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0 // 0 = unlimited
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            
            var loadedImages: [UIImage] = []
            let group = DispatchGroup()
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }
                        if let image = object as? UIImage {
                            loadedImages.append(image)
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                if !loadedImages.isEmpty {
                    self.parent.selectedImages = loadedImages
                }
            }
        }
    }
}
