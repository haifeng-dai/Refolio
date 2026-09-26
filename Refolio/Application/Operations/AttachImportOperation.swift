import Foundation

/// Copy file into the library store then record it on the item.
/// On persistence failure the copied file is removed (compensating action).
@MainActor
struct AttachImportOperation {
    private let repository: any ItemRepository
    private let attachmentFileStore: any AttachmentFileStore

    init(repository: any ItemRepository, attachmentFileStore: any AttachmentFileStore) {
        self.repository = repository
        self.attachmentFileStore = attachmentFileStore
    }

    func execute(
        from sourceURL: URL,
        originalFileName: String,
        role: AttachmentRole,
        to itemID: UUID
    ) async throws {
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
}
