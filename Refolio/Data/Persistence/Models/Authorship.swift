import Foundation
import SwiftData

/// Joins an author to an item while preserving author order for citations.
@Model
final class Authorship {
    @Attribute(.unique) var id: UUID
    var position: Int
    var role: String?
    var item: Item?
    var author: Author?

    init(
        id: UUID = UUID(),
        position: Int,
        role: String? = nil,
        item: Item? = nil,
        author: Author? = nil
    ) {
        self.id = id
        self.position = position
        self.role = role
        self.item = item
        self.author = author
    }
}
