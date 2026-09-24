import Foundation
import SwiftData

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var title: String
    var abstract: String?
    var doi: String?
    var publicationYear: Int?
    var publicationMonth: Int?
    var publicationDay: Int?
    var volume: String?
    var issue: String?
    var pageRange: String?
    var urlString: String?
    var createdAt: Date
    var updatedAt: Date
    var isTrashed: Bool

    var publication: Publication?

    @Relationship(deleteRule: .cascade, inverse: \Authorship.item)
    var authorships: [Authorship] = []

    @Relationship(deleteRule: .cascade, inverse: \Attachment.item)
    var attachments: [Attachment] = []

    @Relationship(deleteRule: .cascade, inverse: \FolderMembership.item)
    var folderMemberships: [FolderMembership] = []

    init(
        id: UUID = UUID(),
        title: String,
        abstract: String? = nil,
        doi: String? = nil,
        publicationYear: Int? = nil,
        publicationMonth: Int? = nil,
        publicationDay: Int? = nil,
        volume: String? = nil,
        issue: String? = nil,
        pageRange: String? = nil,
        urlString: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isTrashed: Bool = false,
        publication: Publication? = nil
    ) {
        self.id = id
        self.title = title
        self.abstract = abstract
        self.doi = doi
        self.publicationYear = publicationYear
        self.publicationMonth = publicationMonth
        self.publicationDay = publicationDay
        self.volume = volume
        self.issue = issue
        self.pageRange = pageRange
        self.urlString = urlString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isTrashed = isTrashed
        self.publication = publication
    }
}
