import Foundation

struct DOIMetadata: Equatable {
    let doi: String
    let title: String?
    let abstract: String?
    let publicationYear: Int?
    let publicationMonth: Int?
    let publicationDay: Int?
    let volume: String?
    let issue: String?
    let pageRange: String?
    let urlString: String?
    let authors: [DOIAuthor]?
    let publicationTitle: String?
    let literatureType: String?
}

struct DOIAuthor: Equatable {
    let givenName: String?
    let familyName: String?
    let literalName: String?
    let orcid: String?
}

enum DOIUpdateField: String, CaseIterable, Hashable, Identifiable {
    case title
    case abstract
    case publicationDate
    case volume
    case issue
    case pageRange
    case url
    case authors
    case publication

    var id: Self { self }
}

enum DOIUpdateChoice: String, CaseIterable, Hashable {
    case keepLocal
    case useRemote
}

struct DOIUpdatePlan {
    let itemID: UUID
    let local: LibraryItem
    let remote: DOIMetadata
    let selectedFields: Set<DOIUpdateField>
}

struct DOIUpdatePreview: Identifiable {
    let itemID: UUID
    let local: LibraryItem
    let remote: DOIMetadata
    let changedFields: Set<DOIUpdateField>

    var id: UUID { itemID }
}

enum DOIUpdateError: LocalizedError {
    case missingDOI
    case mismatchedDOI
    case noChanges

    var errorDescription: String? {
        switch self {
        case .missingDOI:
            "This item does not have a valid DOI."
        case .mismatchedDOI:
            "The DOI returned by the metadata service does not match this item."
        case .noChanges:
            "The local metadata is already identical to the DOI record."
        }
    }
}
