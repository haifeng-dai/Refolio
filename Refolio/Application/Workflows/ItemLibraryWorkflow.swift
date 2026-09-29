import Foundation
import UniformTypeIdentifiers

@MainActor
struct ItemLibraryWorkflow {
    private let repository: any ItemRepository
    private let attachmentFileStore: any AttachmentFileStore
    private let itemCreate: ItemCreateOperation
    private let attachImport: AttachImportOperation
    private let doiLookup: DOILookupOperation
    private let doiUpdate: DOIUpdateOperation

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
        self.doiUpdate = DOIUpdateOperation()
    }

    func lookupDOI(_ rawDOI: String) async throws -> ItemDraft {
        try await doiLookup.execute(rawDOI: rawDOI)
    }

    func lookupDOIMetadata(_ rawDOI: String) async throws -> DOIMetadata {
        try await doiLookup.executeMetadata(rawDOI: rawDOI)
    }

    func prepareDOIUpdate(for item: LibraryItem, remote: DOIMetadata) throws -> DOIUpdatePreview {
        try doiUpdate.prepare(local: item, remote: remote)
    }

    func updateItemByDOI(_ plan: DOIUpdatePlan) throws {
        let draft = try doiUpdate.mergedDraft(for: plan)
        try itemCreate.executeUpdate(plan.itemID, from: draft)
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

    func addItems(_ itemIDs: Set<UUID>, to folderID: UUID) throws {
        try repository.add(itemIDs, to: folderID)
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
        let validPointX = position.pointX.map { $0.isFinite } ?? true
        let validPointY = position.pointY.map { $0.isFinite } ?? true
        guard position.pageIndex >= 0,
              validPointX,
              validPointY,
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

    func fetchTextHighlights(for attachmentID: UUID, in itemID: UUID) throws -> [TextHighlight] {
        try repository.fetchTextHighlights(for: attachmentID, in: itemID)
    }

    func createTextHighlight(_ draft: TextHighlightDraft, for attachmentID: UUID, in itemID: UUID) throws -> TextHighlight {
        let selectedText = draft.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty,
              !draft.pages.isEmpty,
              Set(draft.pages.map(\.pageIndex)).count == draft.pages.count,
              draft.pages.allSatisfy({ page in
                  page.pageIndex >= 0 && !page.rectangles.isEmpty && page.rectangles.allSatisfy(Self.isValidHighlightRectangle)
              }),
              Self.isValidHighlightColor(draft.color) else {
            throw TextHighlightError.invalidGeometry
        }

        let normalizedDraft = TextHighlightDraft(
            selectedText: selectedText,
            color: draft.color,
            pages: draft.pages.sorted { $0.pageIndex < $1.pageIndex }
        )
        return try repository.createTextHighlight(normalizedDraft, for: attachmentID, in: itemID)
    }

    func updateTextHighlightGeometry(
        _ pages: [TextHighlightPage],
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        guard !pages.isEmpty,
              Set(pages.map(\.pageIndex)).count == pages.count,
              pages.allSatisfy({ page in
                  page.pageIndex >= 0 && !page.rectangles.isEmpty && page.rectangles.allSatisfy(Self.isValidHighlightRectangle)
              }) else {
            throw TextHighlightError.invalidGeometry
        }

        return try repository.updateTextHighlightGeometry(
            pages.sorted { $0.pageIndex < $1.pageIndex },
            for: highlightID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func deleteTextHighlight(
        _ highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws {
        try repository.deleteTextHighlight(highlightID, attachmentID: attachmentID, in: itemID)
    }

    func updateTextHighlightColor(
        _ color: TextHighlightColor,
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        guard Self.isValidHighlightColor(color) else { throw TextHighlightError.invalidGeometry }
        return try repository.updateTextHighlightColor(
            color,
            for: highlightID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func fetchRectangleMarks(for attachmentID: UUID, in itemID: UUID) throws -> [RectangleMark] {
        try repository.fetchRectangleMarks(for: attachmentID, in: itemID)
    }

    func createRectangleMark(
        _ draft: RectangleMarkDraft,
        for attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark {
        guard draft.pageIndex >= 0,
              draft.x.isFinite,
              draft.y.isFinite,
              draft.width.isFinite,
              draft.height.isFinite,
              draft.width > 0,
              draft.height > 0 else {
            throw RectangleMarkError.invalidGeometry
        }

        return try repository.createRectangleMark(draft, for: attachmentID, in: itemID)
    }

    func deleteRectangleMark(
        _ markID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws {
        try repository.deleteRectangleMark(markID, attachmentID: attachmentID, in: itemID)
    }

    func updateRectangleMarkColor(
        _ color: TextHighlightColor,
        for markID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark {
        guard Self.isValidHighlightColor(color) else { throw RectangleMarkError.invalidGeometry }
        return try repository.updateRectangleMarkColor(
            color,
            for: markID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func fetchAnnotationComments(for attachmentID: UUID, in itemID: UUID) throws -> [AnnotationComment] {
        try repository.fetchAnnotationComments(for: attachmentID, in: itemID)
    }

    func createAnnotationComment(
        _ draft: AnnotationCommentDraft,
        for annotationID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> AnnotationComment {
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AnnotationCommentError.empty }
        return try repository.createAnnotationComment(
            AnnotationCommentDraft(content: content),
            for: annotationID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func updateAnnotationComment(
        _ commentID: UUID,
        content: String,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> AnnotationComment {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AnnotationCommentError.empty }
        return try repository.updateAnnotationComment(
            commentID,
            content: content,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func deleteAnnotationComment(
        _ commentID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws {
        try repository.deleteAnnotationComment(commentID, attachmentID: attachmentID, in: itemID)
    }

    private static func isValidHighlightRectangle(_ rectangle: TextHighlightRectangle) -> Bool {
        rectangle.x.isFinite && rectangle.y.isFinite
            && rectangle.width.isFinite && rectangle.height.isFinite
            && rectangle.width > 0 && rectangle.height > 0
    }

    private static func isValidHighlightColor(_ color: TextHighlightColor) -> Bool {
        [color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
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

private enum TextHighlightError: LocalizedError {
    case invalidGeometry

    var errorDescription: String? {
        "The selected text could not be mapped to valid PDF geometry. Please select the text again."
    }
}

private enum RectangleMarkError: LocalizedError {
    case invalidGeometry

    var errorDescription: String? {
        "The rectangle annotation has invalid page geometry."
    }
}

private enum AnnotationCommentError: LocalizedError {
    case empty

    var errorDescription: String? {
        "The annotation comment cannot be empty."
    }
}
