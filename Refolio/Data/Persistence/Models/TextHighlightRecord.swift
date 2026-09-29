import Foundation
import SwiftData

@Model
final class TextHighlightRecord {
    @Attribute(.unique) var id: UUID
    var selectedText: String
    var createdAt: Date
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
    var colorAlpha: Double
    var geometryData: Data

    var attachment: Attachment?

    init(
        id: UUID = UUID(),
        selectedText: String,
        createdAt: Date = .now,
        color: TextHighlightColor,
        geometryData: Data,
        attachment: Attachment? = nil
    ) {
        self.id = id
        self.selectedText = selectedText
        self.createdAt = createdAt
        self.colorRed = color.red
        self.colorGreen = color.green
        self.colorBlue = color.blue
        self.colorAlpha = color.alpha
        self.geometryData = geometryData
        self.attachment = attachment
    }

    var color: TextHighlightColor {
        TextHighlightColor(red: colorRed, green: colorGreen, blue: colorBlue, alpha: colorAlpha)
    }
}
