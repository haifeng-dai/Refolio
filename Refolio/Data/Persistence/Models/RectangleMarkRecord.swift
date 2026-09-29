import Foundation
import SwiftData

@Model
final class RectangleMarkRecord {
    @Attribute(.unique) var id: UUID
    var pageIndex: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var createdAt: Date
    var colorRed: Double = 0.18
    var colorGreen: Double = 0.659
    var colorBlue: Double = 0.898
    var colorAlpha: Double = 1.0

    var attachment: Attachment?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        createdAt: Date = .now,
        color: TextHighlightColor = ZoteroAnnotationColor.blue.borderColor,
        attachment: Attachment? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.colorRed = color.red
        self.colorGreen = color.green
        self.colorBlue = color.blue
        self.colorAlpha = color.alpha
        self.attachment = attachment
    }

    var color: TextHighlightColor {
        TextHighlightColor(red: colorRed, green: colorGreen, blue: colorBlue, alpha: colorAlpha)
    }
}
