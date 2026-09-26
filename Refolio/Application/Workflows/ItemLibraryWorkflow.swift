import Foundation
import UniformTypeIdentifiers

@MainActor
struct ItemLibraryWorkflow {
    private let repository: any ItemRepository
    private let attachmentFileStore: any AttachmentFileStore
    private let itemCreate: ItemCreateOperation
    private let attachImport: AttachImportOperation
    private let doiLookup: DOILookupOperation

    init(
        repository: any ItemRepository,
        attachmentFileStore: any AttachmentFileStore,
        bibliographyClient: any BibliographyClient = CrossrefClient()
    ) {
        self.repository = repository
        self.attachmentFileStore = attachmentFileStore
        self.itemCreate = ItemCreateOperation(repository: repository)
        self.attachImport = AttachImportOperation(repository: repository, attachmentFileStore: attachmentFileStore)
        self.doiLookup = DOILookupOperation(client: bibliographyClient)
    }

    func lookupDOI(_ rawDOI: String) async throws -> ItemDraft {
        try await doiLookup.execute(rawDOI: rawDOI)
    }

    func fetchItems() throws -> [LibraryItem] {
        try repository.fetchAll()
    }

    func fetchFolders() throws -> [LibraryFolder] {
        try repository.fetchFolders()
    }

    func createItem(from draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem {
        try itemCreate.execute(draft, in: folderID)
    }

    func updateItem(_ itemID: UUID, from draft: ItemDraft) throws {
        try itemCreate.executeUpdate(itemID, from: draft)
    }

    func createFolder(named name: String) throws -> LibraryFolder {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FolderNameError.empty }
        return try repository.createFolder(named: name)
    }

    func addItem(_ itemID: UUID, to folderID: UUID) throws {
        try repository.add(itemID, to: folderID)
    }

    func moveToTrash(_ itemID: UUID) throws {
        try repository.moveToTrash(itemID)
    }

    func restore(_ itemID: UUID) throws {
        try repository.restore(itemID)
    }

    func importAttachment(from sourceURL: URL, originalFileName: String, role: AttachmentRole, to itemID: UUID) async throws {
        try await attachImport.execute(
            from: sourceURL,
            originalFileName: originalFileName,
            role: role,
            to: itemID
        )
    }

    func openAttachment(_ attachmentID: UUID, for itemID: UUID) async throws -> AttachmentOpenDisposition {
        let attachment = try repository.attachmentFile(attachmentID, in: itemID)
        if isPDF(attachment) {
            return .inAppPDF
        }
        try await attachmentFileStore.open(relativePath: attachment.managedRelativePath)
        return .external
    }

    func pdfDocument(_ attachmentID: UUID, for itemID: UUID) async throws -> AttachmentDocument {
        let attachment = try repository.attachmentFile(attachmentID, in: itemID)
        guard isPDF(attachment) else { throw AttachmentReaderError.notPDF }
        return AttachmentDocument(
            fileName: attachment.fileName,
            url: try await attachmentFileStore.url(for: attachment.managedRelativePath),
            lastReadPosition: attachment.lastReadPosition
        )
    }

    func saveReadingPosition(_ position: PDFReadingPosition, for attachmentID: UUID, in itemID: UUID) throws {
        let validZoom = position.zoom.map { $0.isFinite && $0 > 0 } ?? true
        guard position.pageIndex >= 0,
              (position.pointX == nil && position.pointY == nil)
                || (position.pointX?.isFinite == true && position.pointY?.isFinite == true),
              validZoom else {
            throw AttachmentReaderError.invalidReadingPosition
        }
        try repository.saveReadingPosition(position, for: attachmentID, in: itemID)
    }

    func fetchNotes(for itemID: UUID) throws -> [LiteratureNote] {
        try repository.fetchNotes(for: itemID)
    }

    func createNote(_ draft: LiteratureNoteDraft, for itemID: UUID) throws -> LiteratureNote {
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw LiteratureNoteError.empty }
        guard draft.sourcePageIndex.map({ $0 >= 0 }) ?? true,
              draft.sourcePageIndex == nil || draft.sourceAttachmentID != nil else {
            throw LiteratureNoteError.invalidSource
        }
        return try repository.createNote(
            LiteratureNoteDraft(
                content: content,
                sourceAttachmentID: draft.sourceAttachmentID,
                sourcePageIndex: draft.sourcePageIndex
            ),
            for: itemID
        )
    }

    func updateNote(_ noteID: UUID, content: String, in itemID: UUID) throws -> LiteratureNote {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw LiteratureNoteError.empty }
        return try repository.updateNote(noteID, content: content, in: itemID)
    }

    func deleteNote(_ noteID: UUID, in itemID: UUID) throws {
        try repository.deleteNote(noteID, in: itemID)
    }

    private func isPDF(_ attachment: AttachmentFileReference) -> Bool {
        let type = attachment.contentTypeIdentifier.flatMap { UTType($0) }
            ?? UTType(filenameExtension: URL(fileURLWithPath: attachment.fileName).pathExtension)
        return type?.conforms(to: .pdf) == true
    }
}

private enum FolderNameError: LocalizedError {
    case empty

    var errorDescription: String? { "A folder name is required." }
}

private enum AttachmentReaderError: LocalizedError {
    case notPDF
    case invalidReadingPosition

    var errorDescription: String? {
        switch self {
        case .notPDF: "This attachment is not a PDF."
        case .invalidReadingPosition: "The PDF reading position is invalid."
        }
    }
}

private enum LiteratureNoteError: LocalizedError {
    case empty
    case invalidSource

    var errorDescription: String? {
        switch self {
        case .empty: "A note cannot be empty."
        case .invalidSource: "The note source is invalid."
        }
    }
}
