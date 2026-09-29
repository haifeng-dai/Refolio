import Foundation
import SwiftData

@Model
final class AnnotationCommentRecord {
    @Attribute(.unique) var id: UUID
    var annotationID: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date

    var attachment: Attachment?

    init(
        id: UUID = UUID(),
        annotationID: UUID,
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        attachment: Attachment? = nil
    ) {
        self.id = id
        self.annotationID = annotationID
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachment = attachment
    }
}
