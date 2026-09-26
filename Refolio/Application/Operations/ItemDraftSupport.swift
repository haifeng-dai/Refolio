import Foundation

enum ItemDraftError: LocalizedError {
    case missingTitle
    case invalidYear
    case invalidMonth
    case invalidDay

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            "A title is required."
        case .invalidYear:
            "Enter a valid publication year."
        case .invalidMonth:
            "The publication month must be between 1 and 12."
        case .invalidDay:
            "The publication date is not valid."
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
