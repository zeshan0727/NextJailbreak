import SwiftUI
import PhotosUI
import Photos

struct ContentView: View {
    enum Layout: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case stacked = "Stacked"
        
        var id: String { rawValue }
    }
    
    @State private var image1: UIImage? = nil
    @State private var image2: UIImage? = nil
    @State private var showingPickerForImage1 = false
    @State private var showingPickerForImage2 = false
    @State private var selectedLayout: Layout = .sideBySide
    @State private var combinedImage: UIImage? = nil
    @State private var showingPreview = false
    
    @State private var showPhotoLibraryDeniedAlert = false
    @State private var photoLibraryDeniedMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 20) {
                        VStack(spacing: 8) {
                            ZStack {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(12)
                                if let image1 {
                                    Image(uiImage: image1)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(12)
                                } else {
                                    Text("Select Image 1")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityLabel("Image 1 placeholder")
                            Button(action: {
                                checkPhotoLibraryAuthorization(forImage: 1)
                            }) {
                                Text("Choose Image")
                                    .font(.body)
                                    .frame(minWidth: 140, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Choose Image 1 from photo library")
                        }
                        VStack(spacing: 8) {
                            ZStack {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(12)
                                if let image2 {
                                    Image(uiImage: image2)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(12)
                                } else {
                                    Text("Select Image 2")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityLabel("Image 2 placeholder")
                            Button(action: {
                                checkPhotoLibraryAuthorization(forImage: 2)
                            }) {
                                Text("Choose Image")
                                    .font(.body)
                                    .frame(minWidth: 140, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Choose Image 2 from photo library")
                        }
                    }
                    Picker("Layout", selection: $selectedLayout) {
                        ForEach(Layout.allCases) { layout in
                            Text(layout.rawValue).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .accessibilityLabel("Select layout for combined image")
                    
                    Button(action: combineImages) {
                        Text("Combine & Preview")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(image1 == nil || image2 == nil)
                    .padding(.horizontal)
                    .accessibilityLabel("Combine selected images and preview")
                }
                .padding()
            }
            .navigationTitle("Image Combiner")
            .sheet(isPresented: $showingPickerForImage1) {
                PhotoPicker(selectedImage: $image1)
            }
            .sheet(isPresented: $showingPickerForImage2) {
                PhotoPicker(selectedImage: $image2)
            }
            .alert("Photo Library Access Denied", isPresented: $showPhotoLibraryDeniedAlert, actions: {
                Button("OK", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }, message: {
                Text(photoLibraryDeniedMessage)
            })
            .navigationDestination(isPresented: $showingPreview) {
                if let combinedImage {
                    PreviewView(image: combinedImage)
                }
            }
        }
    }
    
    private func checkPhotoLibraryAuthorization(forImage imageNumber: Int) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            openPicker(forImage: imageNumber)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        openPicker(forImage: imageNumber)
                    } else {
                        photoLibraryDeniedMessage = "Please enable photo library access in Settings to select images."
                        showPhotoLibraryDeniedAlert = true
                    }
                }
            }
        case .denied, .restricted:
            photoLibraryDeniedMessage = "Please enable photo library access in Settings to select images."
            showPhotoLibraryDeniedAlert = true
        @unknown default:
            photoLibraryDeniedMessage = "Unknown photo library authorization status."
            showPhotoLibraryDeniedAlert = true
        }
    }
    
    private func openPicker(forImage imageNumber: Int) {
        if imageNumber == 1 {
            showingPickerForImage1 = true
        } else {
            showingPickerForImage2 = true
        }
    }
    
    private func combineImages() {
        guard let image1, let image2 else { return }
        if let combined = ImageCombiner.combine(image1: image1, image2: image2, layout: selectedLayout) {
            combinedImage = combined
            showingPreview = true
        } else {
            photoLibraryDeniedMessage = "Failed to combine images. Please try again."
            showPhotoLibraryDeniedAlert = true
        }
    }
}

private struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.filter = .images
        config.selectionLimit = 1
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
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        if let uiImage = image as? UIImage {
                            self.parent.selectedImage = uiImage
                        }
                    }
                }
            }
        }
    }
}

private struct PreviewView: View {
    let image: UIImage
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack {
            ScrollView([.horizontal, .vertical]) {
                ZoomableScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Combined image preview")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(UIColor.systemBackground))
            
            HStack(spacing: 20) {
                Button(action: saveImage) {
                    if isSaving {
                        ProgressView()
                            .frame(minWidth: 100, minHeight: 44)
                    } else {
                        Text("Save to Photos")
                            .frame(minWidth: 100, minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Save combined image to photo library")
                .disabled(isSaving)
                
                Button(action: { dismiss() }) {
                    Text("Back")
                        .frame(minWidth: 100, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back to image selection screen")
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .alert("Save Failed", isPresented: $showSaveErrorAlert) {
            Button("Retry") {
                saveImage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func saveImage() {
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized || status == .limited {
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        isSaving = false
                        if success {
                            dismiss()
                        } else {
                            saveErrorMessage = error?.localizedDescription ?? "Unknown error occurred while saving."
                            showSaveErrorAlert = true
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    isSaving = false
                    saveErrorMessage = "Photo library access denied. Please enable access in Settings to save images."
                    showSaveErrorAlert = true
                }
            }
        }
    }
}

private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostedView)
        
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        var hostingController: UIHostingController<Content>
        
        init(_ parent: ZoomableScrollView) {
            self.parent = parent
            hostingController = UIHostingController(rootView: parent.content)
            hostingController.view.backgroundColor = .clear
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }
    }
}

private struct ImageCombiner {
    static func combine(image1: UIImage, image2: UIImage, layout: ContentView.Layout) -> UIImage? {
        switch layout {
        case .sideBySide:
            return combineSideBySide(image1: image1, image2: image2)
        case .stacked:
            return combineStacked(image1: image1, image2: image2)
        }
    }
    
    private static func combineSideBySide(image1: UIImage, image2: UIImage) -> UIImage? {
        // Calculate combined size
        // We want to keep aspect ratio and scale images to have same height
        let maxHeight = max(image1.size.height, image2.size.height)
        
        // Scale images to have same height = maxHeight
        let scale1 = maxHeight / image1.size.height
        let scale2 = maxHeight / image2.size.height
        
        let newWidth1 = image1.size.width * scale1
        let newWidth2 = image2.size.width * scale2
        
        let combinedSize = CGSize(width: newWidth1 + newWidth2, height: maxHeight)
        
        UIGraphicsBeginImageContextWithOptions(combinedSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        image1.draw(in: CGRect(x: 0, y: 0, width: newWidth1, height: maxHeight))
        image2.draw(in: CGRect(x: newWidth1, y: 0, width: newWidth2, height: maxHeight))
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private static func combineStacked(image1: UIImage, image2: UIImage) -> UIImage? {
        // Calculate combined size
        // We want to keep aspect ratio and scale images to have same width
        let maxWidth = max(image1.size.width, image2.size.width)
        
        // Scale images to have same width = maxWidth
        let scale1 = maxWidth / image1.size.width
        let scale2 = maxWidth / image2.size.width
        
        let newHeight1 = image1.size.height * scale1
        let newHeight2 = image2.size.height * scale2
        
        let combinedSize = CGSize(width: maxWidth, height: newHeight1 + newHeight2)
        
        UIGraphicsBeginImageContextWithOptions(combinedSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        image1.draw(in: CGRect(x: 0, y: 0, width: maxWidth, height: newHeight1))
        image2.draw(in: CGRect(x: 0, y: newHeight1, width: maxWidth, height: newHeight2))
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
