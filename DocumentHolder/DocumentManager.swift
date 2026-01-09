import Foundation
import UniformTypeIdentifiers

class DocumentManager: ObservableObject {
    @Published var documents: [DocumentItem] = []
    @Published var trash: [DocumentItem] = []
    
    struct DocumentItem: Identifiable, Equatable {
        let id = UUID()
        var fileName: String
        var fileURL: URL
        let fileType: UTType
        var isLocked: Bool = false
        let addedDate: Date = Date()
        var category: Category = .other
    }
    
    enum Category: String, CaseIterable {
        case passports = "Passports & IDs"
        case cv = "CVs & Certificates"
        case tax = "Tax & Receipts"
        case license = "Driver License"
        case other = "Other"
        case trash = "Trash"
    }
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    init() {
        loadDocuments()
    }
    
    func loadDocuments() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            documents = fileURLs.compactMap { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
                let item = DocumentItem(fileName: url.lastPathComponent, fileURL: url, fileType: type)
                return assignCategory(to: item)
            }
            documents.sort { $0.addedDate > $1.addedDate }
        } catch {
            print("Error loading documents: \(error)")
        }
    }
    
    func saveDocument(from sourceURL: URL, customName: String?) {
        var baseName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseName == nil || baseName!.isEmpty {
            baseName = sourceURL.deletingPathExtension().lastPathComponent
        }
        
        let originalExtension = sourceURL.pathExtension
        let sanitizedBaseName = baseName!.isEmpty ? "Untitled Document" : baseName!
        let proposedFileName = sanitizedBaseName + (originalExtension.isEmpty ? "" : ".\(originalExtension)")
        
        var destinationURL = documentsDirectory.appendingPathComponent(proposedFileName)
        destinationURL = avoidOverwrite(url: destinationURL)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: destinationURL.path)
            
            let type = UTType(filenameExtension: destinationURL.pathExtension) ?? .data
            
            var newItem = DocumentItem(fileName: destinationURL.lastPathComponent, fileURL: destinationURL, fileType: type)
            newItem = assignCategory(to: newItem)
            
            documents.insert(newItem, at: 0)
            
            try? FileManager.default.removeItem(at: sourceURL)
        } catch {
            print("Error saving document: \(error)")
        }
    }
    
    private func avoidOverwrite(url: URL) -> URL {
        var candidate = url
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nameWithoutExt = (url.lastPathComponent as NSString).deletingPathExtension
            let ext = url.pathExtension
            let newName = "\(nameWithoutExt) (\(counter)).\(ext)"
            candidate = url.deletingLastPathComponent().appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }
    
    private func assignCategory(to item: DocumentItem) -> DocumentItem {
        var mutableItem = item
        let name = item.fileName.lowercased()
        
        if name.contains("passport") || name.contains("id") || name.contains("identity") {
            mutableItem.category = .passports
        } else if name.contains("cv") || name.contains("resume") || name.contains("certificate") {
            mutableItem.category = .cv
        } else if name.contains("tax") || name.contains("receipt") || name.contains("invoice") {
            mutableItem.category = .tax
        } else if name.contains("license") || name.contains("driving") {
            mutableItem.category = .license
        } else {
            mutableItem.category = .other
        }
        
        return mutableItem
    }
    
    func lockDocument(_ item: DocumentItem) {
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: item.fileURL.path)
            if let index = documents.firstIndex(where: { $0.id == item.id }) {
                documents[index].isLocked = true
            }
        } catch {
            print("Lock failed: \(error)")
        }
    }
    
    func unlockDocument(_ item: DocumentItem) {
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: item.fileURL.path)
            if let index = documents.firstIndex(where: { $0.id == item.id }) {
                documents[index].isLocked = false
            }
        } catch {
            print("Unlock failed: \(error)")
        }
    }
    
    func temporaryUnlock(_ item: DocumentItem, completion: @escaping () -> Void) {
        // Unlock the file
        unlockDocument(item)
        
        // Schedule re-lock when viewer closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { // Re-lock after 30 seconds of inactivity
            self.lockDocument(item)
        }
        
        completion()
    }
    
    func moveToTrash(_ item: DocumentItem) {
        var trashedItem = item
        trashedItem.category = .trash
        trash.append(trashedItem)
        documents.removeAll { $0.id == item.id }
    }
    
    func restoreFromTrash(_ item: DocumentItem) {
        var restoredItem = item
        restoredItem = assignCategory(to: item)
        documents.append(restoredItem)
        trash.removeAll { $0.id == item.id }
        documents.sort { $0.addedDate > $1.addedDate }
    }
    
    func permanentDeleteFromTrash(_ item: DocumentItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        trash.removeAll { $0.id == item.id }
    }
    
    func deleteDocument(_ item: DocumentItem) {
        moveToTrash(item)
    }
    
    func renameDocument(_ item: DocumentItem, to newName: String) {
        let originalExtension = item.fileURL.pathExtension
        let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = sanitizedName.isEmpty ? "Untitled Document" : sanitizedName
        let newFileName = finalName + (originalExtension.isEmpty ? "" : ".\(originalExtension)")
        
        let newURL = documentsDirectory.appendingPathComponent(newFileName)
        let finalURL = avoidOverwrite(url: newURL)
        
        do {
            try FileManager.default.moveItem(at: item.fileURL, to: finalURL)
            
            if let index = documents.firstIndex(where: { $0.id == item.id }) {
                documents[index].fileName = finalURL.lastPathComponent
                documents[index].fileURL = finalURL
                documents[index] = assignCategory(to: documents[index])
            }
        } catch {
            print("Rename failed: \(error)")
        }
    }
}
