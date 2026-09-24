import Foundation
import SwiftData

@Model
final class Author {
    @Attribute(.unique) var id: UUID
    var givenName: String?
    var familyName: String?
    var literalName: String?
    var orcid: String?

    @Relationship(deleteRule: .cascade, inverse: \Authorship.author)
    var authorships: [Authorship] = []

    init(
        id: UUID = UUID(),
        givenName: String? = nil,
        familyName: String? = nil,
        literalName: String? = nil,
        orcid: String? = nil
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.literalName = literalName
        self.orcid = orcid
    }

    var displayName: String {
        if let literalName, !literalName.isEmpty {
            return literalName
        }

        return [givenName, familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
