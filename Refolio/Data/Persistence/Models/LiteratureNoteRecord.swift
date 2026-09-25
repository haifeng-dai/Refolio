import Foundation
import SwiftData

@Model
final class LiteratureNoteRecord {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var sourcePageIndex: Int?

    var item: Item?
    var sourceAttachment: Attachment?

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sourcePageIndex: Int? = nil,
        item: Item? = nil,
        sourceAttachment: Attachment? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourcePageIndex = sourcePageIndex
        self.item = item
        self.sourceAttachment = sourceAttachment
    }
}
