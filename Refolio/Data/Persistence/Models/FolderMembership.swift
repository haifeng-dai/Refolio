import Foundation
import SwiftData

/// Associates an item with a collection-style folder without duplicating the item.
@Model
final class FolderMembership {
    @Attribute(.unique) var id: UUID
    var addedAt: Date
    var folder: Folder?
    var item: Item?

    init(
        id: UUID = UUID(),
        addedAt: Date = .now,
        folder: Folder? = nil,
        item: Item? = nil
    ) {
        self.id = id
        self.addedAt = addedAt
        self.folder = folder
        self.item = item
    }
}
