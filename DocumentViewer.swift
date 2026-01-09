import SwiftUI
import PDFKit
import QuickLook

struct DocumentViewer: View {
    let document: DocumentManager.DocumentItem
    
    var body: some View {
        if document.fileType.conforms(to: .pdf) {
            PDFViewer(url: document.fileURL)
                .navigationTitle(document.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: document.fileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        } else {
            QuickLookViewer(url: document.fileURL)
                .navigationTitle(document.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: document.fileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

// MARK: - PDFKit Viewer (FAST & SMOOTH for PDFs)
struct PDFViewer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil || pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
            pdfView.autoScales = true
        }
    }
}

// MARK: - QuickLook Viewer (for DOCX, images, etc.)
struct QuickLookViewer: UIViewControllerRepresentable {
    let url: URL
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .pageSheet
        return nav
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let previewController = uiViewController.topViewController as? QLPreviewController {
            previewController.reloadData()
        }
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        
        init(url: URL) {
            self.url = url
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
    }
}
