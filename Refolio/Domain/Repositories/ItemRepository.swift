import Foundation

@MainActor
protocol ItemRepository {
    func fetchAll() throws -> [LibraryItem]
    func fetchFolders() throws -> [LibraryFolder]
    func create(_ draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem
    func update(_ itemID: UUID, from draft: ItemDraft) throws
    func findNonTrashed(doi: String) throws -> [LibraryItem]
    func createFolder(named name: String) throws -> LibraryFolder
    func add(_ itemIDs: Set<UUID>, to folderID: UUID) throws
    func moveToTrash(_ itemID: UUID) throws
    func restore(_ itemID: UUID) throws
    func addAttachment(_ attachment: AttachmentRecord, to itemID: UUID) throws
    func attachmentFile(_ attachmentID: UUID, in itemID: UUID) throws -> AttachmentFileReference
    func saveReadingPosition(_ position: PDFReadingPosition, for attachmentID: UUID, in itemID: UUID) throws
    func fetchNotes(for itemID: UUID) throws -> [LiteratureNote]
    func createNote(_ draft: LiteratureNoteDraft, for itemID: UUID) throws -> LiteratureNote
    func updateNote(_ noteID: UUID, content: String, in itemID: UUID) throws -> LiteratureNote
    func deleteNote(_ noteID: UUID, in itemID: UUID) throws
    func fetchTextHighlights(for attachmentID: UUID, in itemID: UUID) throws -> [TextHighlight]
    func createTextHighlight(_ draft: TextHighlightDraft, for attachmentID: UUID, in itemID: UUID) throws -> TextHighlight
    func updateTextHighlightGeometry(
        _ pages: [TextHighlightPage],
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight
    func deleteTextHighlight(_ highlightID: UUID, attachmentID: UUID, in itemID: UUID) throws
    func updateTextHighlightColor(
        _ color: TextHighlightColor,
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight
    func fetchRectangleMarks(for attachmentID: UUID, in itemID: UUID) throws -> [RectangleMark]
    func createRectangleMark(
        _ draft: RectangleMarkDraft,
        for attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark
    func deleteRectangleMark(_ markID: UUID, attachmentID: UUID, in itemID: UUID) throws
    func updateRectangleMarkColor(
        _ color: TextHighlightColor,
        for markID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark
    func fetchAnnotationComments(for attachmentID: UUID, in itemID: UUID) throws -> [AnnotationComment]
    func createAnnotationComment(
        _ draft: AnnotationCommentDraft,
        for annotationID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> AnnotationComment
    func updateAnnotationComment(
        _ commentID: UUID,
        content: String,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> AnnotationComment
    func deleteAnnotationComment(_ commentID: UUID, attachmentID: UUID, in itemID: UUID) throws
}
