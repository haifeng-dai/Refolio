import Foundation

struct LiteratureNote: Identifiable, Equatable {
    let id: UUID
    let itemID: UUID
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let sourceAttachmentName: String?
    let sourcePageIndex: Int?
}

struct LiteratureNoteDraft {
    var content: String
    var sourceAttachmentID: UUID? = nil
    var sourcePageIndex: Int? = nil
}
