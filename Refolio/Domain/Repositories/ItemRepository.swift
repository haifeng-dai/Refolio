import Foundation

@MainActor
protocol ItemRepository {
    func fetchAll() throws -> [LibraryItem]
    func fetchFolders() throws -> [LibraryFolder]
    func create(_ draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem
    func update(_ itemID: UUID, from draft: ItemDraft) throws
    func createFolder(named name: String) throws -> LibraryFolder
    func add(_ itemID: UUID, to folderID: UUID) throws
    func moveToTrash(_ itemID: UUID) throws
    func restore(_ itemID: UUID) throws
    func addAttachment(_ attachment: AttachmentRecord, to itemID: UUID) throws
    func attachmentFile(_ attachmentID: UUID, in itemID: UUID) throws -> AttachmentFileReference
    func saveReadingPosition(_ position: PDFReadingPosition, for attachmentID: UUID, in itemID: UUID) throws
    func fetchNotes(for itemID: UUID) throws -> [LiteratureNote]
    func createNote(_ draft: LiteratureNoteDraft, for itemID: UUID) throws -> LiteratureNote
    func updateNote(_ noteID: UUID, content: String, in itemID: UUID) throws -> LiteratureNote
    func deleteNote(_ noteID: UUID, in itemID: UUID) throws
}
