import PDFKit
import SwiftUI

struct GeneratedPDFPreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let data: Data
}

struct GeneratedPDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: GeneratedPDFPreviewItem

    var body: some View {
        NavigationStack {
            PDFKitPreview(data: item.data)
                .background(Color(.secondarySystemBackground))
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct PDFKitPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
        }
        uiView.autoScales = true
    }
}
