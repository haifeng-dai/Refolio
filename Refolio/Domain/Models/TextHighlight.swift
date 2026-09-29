import Foundation

struct TextHighlight: Identifiable, Equatable {
    let id: UUID
    let selectedText: String
    let createdAt: Date
    let color: TextHighlightColor
    let pages: [TextHighlightPage]
}

struct TextHighlightDraft {
    var selectedText: String
    var color: TextHighlightColor = ZoteroAnnotationColor.yellow.highlightColor
    var pages: [TextHighlightPage]
}

struct TextHighlightColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let yellow = TextHighlightColor(red: 1, green: 0.86, blue: 0, alpha: 0.42)

    func withAlpha(_ alpha: Double) -> TextHighlightColor {
        TextHighlightColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum ZoteroAnnotationColor: String, CaseIterable, Identifiable {
    case yellow
    case red
    case green
    case blue
    case purple
    case magenta
    case orange
    case gray

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    private var rgb: TextHighlightColor {
        switch self {
        case .yellow: TextHighlightColor(red: 1.0, green: 0.831, blue: 0.0, alpha: 1.0)
        case .red: TextHighlightColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        case .green: TextHighlightColor(red: 0.373, green: 0.698, blue: 0.212, alpha: 1.0)
        case .blue: TextHighlightColor(red: 0.18, green: 0.659, blue: 0.898, alpha: 1.0)
        case .purple: TextHighlightColor(red: 0.635, green: 0.541, blue: 0.898, alpha: 1.0)
        case .magenta: TextHighlightColor(red: 0.898, green: 0.431, blue: 0.933, alpha: 1.0)
        case .orange: TextHighlightColor(red: 0.945, green: 0.596, blue: 0.216, alpha: 1.0)
        case .gray: TextHighlightColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
        }
    }

    var highlightColor: TextHighlightColor {
        rgb.withAlpha(0.42)
    }

    var borderColor: TextHighlightColor {
        rgb
    }
}

struct TextHighlightPage: Codable, Equatable {
    let pageIndex: Int
    let rectangles: [TextHighlightRectangle]
}

struct TextHighlightRectangle: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
