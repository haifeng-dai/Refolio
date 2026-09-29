import Foundation

struct RectangleMark: Identifiable, Equatable {
    let id: UUID
    let pageIndex: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let createdAt: Date
    let color: TextHighlightColor
}

struct RectangleMarkDraft {
    let pageIndex: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var color: TextHighlightColor = ZoteroAnnotationColor.blue.borderColor
}
