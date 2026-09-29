import Foundation

struct AuthorDraft: Equatable {
    var givenName: String?
    var familyName: String?
    var literalName: String?
    var orcid: String?

    init(
        givenName: String? = nil,
        familyName: String? = nil,
        literalName: String? = nil,
        orcid: String? = nil
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.literalName = literalName
        self.orcid = orcid
    }

    var hasName: Bool {
        givenName != nil || familyName != nil || literalName != nil
    }

    func normalized() -> AuthorDraft? {
        let normalized = AuthorDraft(
            givenName: givenName?.trimmedOrNil,
            familyName: familyName?.trimmedOrNil,
            literalName: literalName?.trimmedOrNil,
            orcid: orcid?.trimmedOrNil.flatMap(ORCIDString.normalize)
                ?? orcid?.trimmedOrNil
        )
        return normalized.hasName ? normalized : nil
    }
}

enum AuthorNameFormatter {
    static func inline(_ author: AuthorDraft) -> String {
        if let familyName = author.familyName, !familyName.isEmpty,
           let givenName = author.givenName, !givenName.isEmpty {
            return "\(familyName), \(givenName)"
        }
        let structuredName = [author.givenName, author.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !structuredName.isEmpty {
            return structuredName
        }
        return author.literalName ?? ""
    }

    static func inline(_ authors: [AuthorDraft]) -> String {
        authors.map(inline).joined(separator: ", ")
    }
}

struct ItemDraft {
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
    var authors: [AuthorDraft]
    var publicationTitle: String?
    var literatureType: String?

    init(
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
        publicationTitle: String? = nil,
        literatureType: String? = nil,
        authorNames: [String] = [],
        authors: [AuthorDraft]? = nil
    ) {
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
        self.authors = authors ?? authorNames.map {
            AuthorDraft(literalName: $0)
        }
        self.publicationTitle = publicationTitle
        self.literatureType = literatureType
    }

    var authorNames: [String] {
        authors.map(AuthorNameFormatter.inline)
    }
}

struct LibraryItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let abstract: String?
    let doi: String?
    let publicationYear: Int?
    let publicationMonth: Int?
    let publicationDay: Int?
    let volume: String?
    let issue: String?
    let pageRange: String?
    let urlString: String?
    let authors: [AuthorDraft]
    let publicationTitle: String?
    let literatureType: String?
    let folderIDs: [UUID]
    let isTrashed: Bool
    let attachments: [LibraryAttachment]

    init(
        id: UUID,
        title: String,
        abstract: String?,
        doi: String?,
        publicationYear: Int?,
        publicationMonth: Int?,
        publicationDay: Int?,
        volume: String?,
        issue: String?,
        pageRange: String?,
        urlString: String?,
        publicationTitle: String?,
        literatureType: String?,
        folderIDs: [UUID],
        isTrashed: Bool,
        attachments: [LibraryAttachment],
        authors: [AuthorDraft]? = nil,
        authorNames: [String] = []
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
        self.authors = authors ?? authorNames.map {
            AuthorDraft(literalName: $0)
        }
        self.publicationTitle = publicationTitle
        self.literatureType = literatureType
        self.folderIDs = folderIDs
        self.isTrashed = isTrashed
        self.attachments = attachments
    }

    var authorNames: [String] {
        authors.map(AuthorNameFormatter.inline)
    }
}

enum AttachmentRole: String, CaseIterable, Identifiable {
    case main
    case supplementary
    case code
    case data
    case other

    var id: String { rawValue }
}

struct LibraryAttachment: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let role: AttachmentRole
}

struct AttachmentRecord {
    let id: UUID
    let fileName: String
    let role: AttachmentRole
    let contentTypeIdentifier: String?
    let byteCount: Int64?
    let managedRelativePath: String
}

struct AttachmentFileReference {
    let fileName: String
    let contentTypeIdentifier: String?
    let managedRelativePath: String
    let lastReadPosition: PDFReadingPosition?
}

struct AttachmentDocument {
    let fileName: String
    let url: URL
    let lastReadPosition: PDFReadingPosition?
}

struct PDFReadingPosition: Equatable {
    let pageIndex: Int
    let pointX: Double?
    let pointY: Double?
    let zoom: Double?
}

enum AttachmentOpenDisposition {
    case inAppPDF
    case external
}

struct LibraryFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let itemCount: Int
}

enum FolderSelection: Hashable {
    case allItems
    case unfiled
    case trash
    case folder(UUID)
}

enum ItemAttachmentFilter: String, CaseIterable, Identifiable {
    case all
    case hasMainFile
    case missingMainFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Items"
        case .hasMainFile: "With Main File (PDF)"
        case .missingMainFile: "Without Main File"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .hasMainFile: "doc.richtext"
        case .missingMainFile: "doc.badge.ellipsis"
        }
    }
}

extension LibraryItem {
    var hasMainAttachment: Bool {
        attachments.contains { $0.role == .main }
    }
}
