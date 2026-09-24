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
    func attachmentPath(_ attachmentID: UUID, in itemID: UUID) throws -> String
}
