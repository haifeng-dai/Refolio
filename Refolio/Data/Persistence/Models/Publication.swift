import Foundation
import SwiftData

@Model
final class Publication {
    @Attribute(.unique) var id: UUID
    var title: String
    /// The publication is the authority for the literature type of its items.
    var literatureType: String
    var abbreviation: String?
    var publisher: String?
    var issn: String?
    var isbn: String?
    var urlString: String?

    @Relationship(deleteRule: .nullify, inverse: \Item.publication)
    var items: [Item] = []

    init(
        id: UUID = UUID(),
        title: String,
        literatureType: String,
        abbreviation: String? = nil,
        publisher: String? = nil,
        issn: String? = nil,
        isbn: String? = nil,
        urlString: String? = nil
    ) {
        self.id = id
        self.title = title
        self.literatureType = literatureType
        self.abbreviation = abbreviation
        self.publisher = publisher
        self.issn = issn
        self.isbn = isbn
        self.urlString = urlString
    }
}
