import Foundation

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
    var authorNames: [String]
    var publicationTitle: String?
    var literatureType: String?
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
    let authorNames: [String]
    let publicationTitle: String?
    let literatureType: String?
    let folderIDs: [UUID]
    let isTrashed: Bool
    let attachments: [LibraryAttachment]
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
