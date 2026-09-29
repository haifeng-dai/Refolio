import Foundation

struct AnnotationComment: Identifiable, Equatable {
    let id: UUID
    let annotationID: UUID
    let content: String
    let createdAt: Date
    let updatedAt: Date
}

struct AnnotationCommentDraft {
    var content: String
}
