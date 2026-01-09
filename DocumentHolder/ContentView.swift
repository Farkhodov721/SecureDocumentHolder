import SwiftUI
import PhotosUI
import QuickLook

struct ContentView: View {
    @StateObject private var documentManager = DocumentManager()
    
    // MARK: - States
    @State private var isFABExpanded = false
    
    @State private var showingDocumentPicker = false
    @State private var pickedURL: URL?
    
    @State private var photosItem: PhotosPickerItem?
    
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    
    @State private var showingRenameAlert = false
    @State private var proposedFileName = ""
    @State private var renameTarget: DocumentManager.DocumentItem?
    
    @State private var selectedDocument: DocumentManager.DocumentItem?
    @State private var showingViewer = false
    
    @State private var searchText = ""
    
    @State private var showingTrash = false
    
    @State private var showPhotosPicker = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                documentGrid
                
                fabOverlay
            }
            .navigationTitle("Secure Vault")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search documents")
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        BiometricAuth.shared.authenticate(reason: "Authenticate to view Trash") { success in
                            if success {
                                showingTrash = true
                            }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(documentManager.trash.isEmpty ? .gray : .red)
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(pickedURL: $pickedURL, onDismiss: handlePickedFile)
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(image: $cameraImage, sourceType: .camera)
                    .ignoresSafeArea()
            }
            .onChange(of: photosItem) { newItem in
                Task {
                    await handlePhotosItem(newItem)
                }
            }
            .onChange(of: cameraImage) { newImage in
                if let image = newImage {
                    handleCameraImage(image)
                }
            }
            .alert("Rename Document", isPresented: $showingRenameAlert) {
                TextField("Name", text: $proposedFileName)
                    .autocapitalization(.none)
                Button("Cancel", role: .cancel) { resetPickerStates() }
                Button("Save") {
                    if let target = renameTarget {
                        documentManager.renameDocument(target, to: proposedFileName.isEmpty ? target.fileName : proposedFileName)
                    } else if let url = pickedURL {
                        documentManager.saveDocument(from: url, customName: proposedFileName.isEmpty ? nil : proposedFileName)
                    }
                    resetPickerStates()
                }
            } message: {
                Text("Enter a custom name (extension preserved)")
            }
            .sheet(isPresented: $showingViewer) {
                if let doc = selectedDocument {
                    DocumentViewer(document: doc)
                }
            }
            .sheet(isPresented: $showingTrash) {
                TrashView(documentManager: documentManager)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Document Grid
    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(filteredDocuments) { document in
                    documentCard(document)
                }
            }
            .padding()
        }
    }
    
    private var filteredDocuments: [DocumentManager.DocumentItem] {
        documentManager.documents.filter { searchText.isEmpty || $0.fileName.lowercased().contains(searchText.lowercased()) }
    }
    
    // MARK: - Document Card
    private func documentCard(_ document: DocumentManager.DocumentItem) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 140)
                    .blur(radius: 8)
                    .overlay(
                        Image(systemName: getDocumentIcon(for: document.fileType))
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.7))
                    )
                
                if document.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                        .padding(6)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Circle())
                        .offset(x: 50, y: -50)
                }
            }
            
            Text(document.fileName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.5), radius: 8)
        .onTapGesture {
            handleTap(document)
        }
        .contextMenu {
            if document.isLocked {
                // Locked → only unlock option
                Button {
                    BiometricAuth.shared.authenticate(reason: "Authenticate to unlock \(document.fileName)") { success in
                        if success {
                            documentManager.unlockDocument(document)
                        }
                    }
                } label: {
                    Label("Unlock File", systemImage: "lock.open")
                }
            } else {
                // Unlocked → lock + other actions (all with Face ID)
                Button {
                    BiometricAuth.shared.authenticate(reason: "Authenticate to lock \(document.fileName)") { success in
                        if success {
                            documentManager.lockDocument(document)
                        }
                    }
                } label: {
                    Label("Lock File", systemImage: "lock")
                }
                
                Button {
                    BiometricAuth.shared.authenticate(reason: "Authenticate to rename \(document.fileName)") { success in
                        if success {
                            proposedFileName = document.fileName
                            renameTarget = document
                            showingRenameAlert = true
                        }
                    }
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Button {
                    BiometricAuth.shared.authenticate(reason: "Authenticate to share \(document.fileName)") { success in
                        if success {
                            let activityVC = UIActivityViewController(activityItems: [document.fileURL], applicationActivities: nil)
                            UIApplication.shared.windows.first?.rootViewController?.present(activityVC, animated: true)
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    BiometricAuth.shared.authenticate(reason: "Authenticate to move \(document.fileName) to Trash") { success in
                        if success {
                            documentManager.moveToTrash(document)
                        }
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
    }


    
    // MARK: - FAB View
    private var fabOverlay: some View {
        VStack(spacing: 16) {
            if isFABExpanded {
                fabButton(title: "Files", icon: "folder.fill", color: .orange) {
                    showingDocumentPicker = true
                    closeFAB()
                }
                
                fabButton(title: "Photos", icon: "photo.on.rectangle", color: .green) {
                    showPhotosPicker = true
                }
                
                fabButton(title: "Camera", icon: "camera.fill", color: .blue) {
                    showingCamera = true
                    closeFAB()
                }
            }
            
            Button {
                withAnimation(.spring()) {
                    isFABExpanded.toggle()
                }
            } label: {
                Image(systemName: isFABExpanded ? "xmark" : "plus")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 90, height: 70)
                    .background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .shadow(color: .blue.opacity(0.6), radius: 20)
                    .rotationEffect(.degrees(isFABExpanded ? 45 : 0))
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .photosPicker(isPresented: $showPhotosPicker, selection: $photosItem, matching: .images)
    }
    
    private func fabButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            .padding()
            .background(color.opacity(0.9))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(radius: 8)
        }
        .padding(.horizontal,50)
    }
    
    private func closeFAB() {
        withAnimation { isFABExpanded = false }
    }
    
    // MARK: - Helpers
    private func getDocumentIcon(for type: UTType) -> String {
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        return "doc"
    }
    
    private func handleTap(_ document: DocumentManager.DocumentItem) {
        if document.isLocked {
            BiometricAuth.shared.authenticate(reason: "Authenticate to view \(document.fileName)") { success in
                if success {
                    // Temporarily unlock for viewing
                    documentManager.temporaryUnlock(document) {
                        selectedDocument = document
                        showingViewer = true
                    }
                }
            }
        } else {
            selectedDocument = document
            showingViewer = true
        }
    }
    
    private func authenticateToLock(_ document: DocumentManager.DocumentItem) {
        BiometricAuth.shared.authenticate(reason: "Lock \(document.fileName)") { success in
            if success {
                documentManager.lockDocument(document)
            }
        }
    }
    
    private func authenticateToUnlock(_ document: DocumentManager.DocumentItem) {
        BiometricAuth.shared.authenticate(reason: "View \(document.fileName)") { success in
            if success {
                documentManager.unlockDocument(document)
                selectedDocument = document
                showingViewer = true
            }
        }
    }
    
    private func handlePickedFile() {
        if let url = pickedURL {
            proposedFileName = url.deletingPathExtension().lastPathComponent
            showingRenameAlert = true
        }
    }
    
    private func handlePhotosItem(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("photo_\(UUID().uuidString).jpg")
            try? data.write(to: tempURL)
            pickedURL = tempURL
            proposedFileName = "Photo"
            showingRenameAlert = true
        }
    }
    
    private func handleCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("scan_\(UUID().uuidString).jpg")
        try? data.write(to: tempURL)
        pickedURL = tempURL
        proposedFileName = "Scan"
        showingRenameAlert = true
        cameraImage = nil
    }
    
    private func resetPickerStates() {
        pickedURL = nil
        photosItem = nil
        cameraImage = nil
        proposedFileName = ""
        renameTarget = nil
    }
}


extension UIApplication {
    var keyWindowPresentedController: UIViewController? {
        var root = self.windows.first?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root
    }
}

// MARK: - Trash View
struct TrashView: View {
    @ObservedObject var documentManager: DocumentManager
    
    var body: some View {
        List {
            ForEach(documentManager.trash) { document in
                HStack {
                    Image(systemName: getDocumentIcon(for: document.fileType))
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    VStack(alignment: .leading) {
                        Text(document.fileName)
                            .foregroundColor(.white)
                        Text("Deleted")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if document.isLocked {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .swipeActions {
                    Button("Restore") {
                        documentManager.restoreFromTrash(document)
                    }
                    .tint(.blue)
                    
                    Button("Delete Forever", role: .destructive) {
                        documentManager.permanentDeleteFromTrash(document)
                    }
                }
            }
        }
        .navigationTitle("Trash")
        .background(Color.black)
        .foregroundColor(.white)
    }
    
    private func getDocumentIcon(for type: UTType) -> String {
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        return "doc"
    }
}

#Preview {
    ContentView()
}
