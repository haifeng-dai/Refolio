import Foundation

struct ManagedAttachmentFile: Sendable {
    let relativePath: String
    let contentTypeIdentifier: String?
    let byteCount: Int64?
}

protocol AttachmentFileStore: Sendable {
    func copy(from sourceURL: URL, attachmentID: UUID, originalFileName: String) async throws -> ManagedAttachmentFile
    func remove(relativePath: String) async throws
    func url(for relativePath: String) async throws -> URL
    func open(relativePath: String) async throws
}
