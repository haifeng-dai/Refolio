import Foundation
import UniformTypeIdentifiers

@MainActor
struct ItemLibraryWorkflow {
    private let repository: any ItemRepository
    private let attachmentFileStore: any AttachmentFileStore

    init(repository: any ItemRepository, attachmentFileStore: any AttachmentFileStore) {
        self.repository = repository
        self.attachmentFileStore = attachmentFileStore
    }

    func fetchItems() throws -> [LibraryItem] {
        try repository.fetchAll()
    }

    func fetchFolders() throws -> [LibraryFolder] {
        try repository.fetchFolders()
    }

    func createItem(from draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem {
        try repository.create(normalized(draft), in: folderID)
    }

    func updateItem(_ itemID: UUID, from draft: ItemDraft) throws {
        try repository.update(itemID, from: normalized(draft))
    }

    private func normalized(_ draft: ItemDraft) throws -> ItemDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ItemDraftError.missingTitle
        }

        try validateDate(year: draft.publicationYear, month: draft.publicationMonth, day: draft.publicationDay)

        return ItemDraft(
            title: title,
            abstract: draft.abstract?.trimmedOrNil,
            doi: draft.doi?.trimmedOrNil,
            publicationYear: draft.publicationYear,
            publicationMonth: draft.publicationMonth,
            publicationDay: draft.publicationDay,
            volume: draft.volume?.trimmedOrNil,
            issue: draft.issue?.trimmedOrNil,
            pageRange: draft.pageRange?.trimmedOrNil,
            urlString: draft.urlString?.trimmedOrNil,
            authorNames: draft.authorNames.compactMap(\.trimmedOrNil),
            publicationTitle: draft.publicationTitle?.trimmedOrNil,
            literatureType: draft.literatureType?.trimmedOrNil
        )
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
        let attachmentID = UUID()
        let file = try await attachmentFileStore.copy(
            from: sourceURL,
            attachmentID: attachmentID,
            originalFileName: originalFileName
        )
        do {
            try repository.addAttachment(
                AttachmentRecord(
                    id: attachmentID,
                    fileName: originalFileName,
                    role: role,
                    contentTypeIdentifier: file.contentTypeIdentifier,
                    byteCount: file.byteCount,
                    managedRelativePath: file.relativePath
                ),
                to: itemID
            )
        } catch {
            try? await attachmentFileStore.remove(relativePath: file.relativePath)
            throw error
        }
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

    private func validateDate(year: Int?, month: Int?, day: Int?) throws {
        if let year, !(1...9999).contains(year) {
            throw ItemDraftError.invalidYear
        }
        if let month, !(1...12).contains(month) {
            throw ItemDraftError.invalidMonth
        }
        if let day, !(1...31).contains(day) {
            throw ItemDraftError.invalidDay
        }

        guard let year, let month, let day else { return }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else {
            throw ItemDraftError.invalidDay
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else {
            throw ItemDraftError.invalidDay
        }
    }
}

private enum FolderNameError: LocalizedError {
    case empty

    var errorDescription: String? { "A folder name is required." }
}

private enum ItemDraftError: LocalizedError {
    case missingTitle
    case invalidYear
    case invalidMonth
    case invalidDay

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            "A title is required."
        case .invalidYear:
            "Enter a valid publication year."
        case .invalidMonth:
            "The publication month must be between 1 and 12."
        case .invalidDay:
            "The publication date is not valid."
        }
    }
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

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
