import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var pickedURL: URL?
    var onDismiss: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [
            .pdf,
            .image,
            .plainText,
            .rtf,
            .spreadsheet,
            .presentation,
            .item  // Fallback for any file
        ]
        
        // Explicit Microsoft Office support
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        if let pptx = UTType(filenameExtension: "pptx") { types.append(pptx) }
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let sourceURL = urls.first else { return }
            
            // Start security-scoped access
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            guard accessGranted else {
                print("Security-scoped access denied")
                parent.onDismiss()
                return
            }
            
            // Copy to safe temporary location immediately
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
            
            do {
                // Clean any old temp file
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                
                parent.pickedURL = tempURL
                parent.onDismiss()
                
            } catch {
                print("Failed to copy file during secure access: \(error)")
                parent.onDismiss()
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onDismiss()
        }
    }
}
