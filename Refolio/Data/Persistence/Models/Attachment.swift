import Foundation
import SwiftData

@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var roleRawValue: String?
    var contentTypeIdentifier: String?
    var byteCount: Int64?
    var importedAt: Date

    /// Set for app-managed files; security-scoped bookmark for externally managed files.
    var managedRelativePath: String?
    var securityScopedBookmark: Data?

    var item: Item?

    init(
        id: UUID = UUID(),
        fileName: String,
        roleRawValue: String? = AttachmentRole.other.rawValue,
        contentTypeIdentifier: String? = nil,
        byteCount: Int64? = nil,
        importedAt: Date = .now,
        managedRelativePath: String? = nil,
        securityScopedBookmark: Data? = nil,
        item: Item? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.roleRawValue = roleRawValue
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.importedAt = importedAt
        self.managedRelativePath = managedRelativePath
        self.securityScopedBookmark = securityScopedBookmark
        self.item = item
    }
}
