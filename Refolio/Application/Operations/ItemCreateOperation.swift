import Foundation

/// Reusable create pipeline: dedup → normalize → persist.
/// Shared by manual entry and future DOI import.
@MainActor
struct ItemCreateOperation {
    private let repository: any ItemRepository

    init(repository: any ItemRepository) {
        self.repository = repository
    }

    func execute(_ draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem {
        try ensureUniqueDOI(draft.doi, excluding: nil)
        return try repository.create(try Self.normalized(draft), in: folderID)
    }

    func executeUpdate(_ itemID: UUID, from draft: ItemDraft) throws {
        try ensureUniqueDOI(draft.doi, excluding: itemID)
        try repository.update(itemID, from: try Self.normalized(draft))
    }

    private func ensureUniqueDOI(_ doi: String?, excluding itemID: UUID?) throws {
        guard let normalizedDOI = doi.flatMap(DOIString.normalize) else { return }
        let hits = try repository.findNonTrashed(doi: normalizedDOI)
            .filter { $0.id != itemID }
        if let conflict = hits.first {
            throw ItemCreateError.duplicateDOI(existingID: conflict.id, title: conflict.title)
        }
    }

    private static func normalized(_ draft: ItemDraft) throws -> ItemDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ItemDraftError.missingTitle
        }
        try validateDate(year: draft.publicationYear, month: draft.publicationMonth, day: draft.publicationDay)

        return ItemDraft(
            title: title,
            abstract: draft.abstract?.trimmedOrNil,
            doi: draft.doi.flatMap(DOIString.normalize) ?? draft.doi?.trimmedOrNil,
            publicationYear: draft.publicationYear,
            publicationMonth: draft.publicationMonth,
            publicationDay: draft.publicationDay,
            volume: draft.volume?.trimmedOrNil,
            issue: draft.issue?.trimmedOrNil,
            pageRange: draft.pageRange?.trimmedOrNil,
            urlString: draft.urlString?.trimmedOrNil,
            authorNames: draft.authorNames.compactMap(\.trimmedOrNil),
            publicationTitle: draft.publicationTitle?.trimmedOrNil,
            literatureType: draft.literatureType?.trimmedOrNil
        )
    }

    private static func validateDate(year: Int?, month: Int?, day: Int?) throws {
        if let year, !(1...9999).contains(year) {
            throw ItemDraftError.invalidYear
        }
        if let month, !(1...12).contains(month) {
            throw ItemDraftError.invalidMonth
        }
        if let day, !(1...31).contains(day) {
            throw ItemDraftError.invalidDay
        }

        guard let year, let month, let day else { return }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else {
            throw ItemDraftError.invalidDay
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else {
            throw ItemDraftError.invalidDay
        }
    }
}

enum ItemCreateError: LocalizedError {
    case duplicateDOI(existingID: UUID, title: String)

    var errorDescription: String? {
        if case let .duplicateDOI(_, title) = self {
            return "A non-trashed item with this DOI already exists: \(title)."
        }
        return nil
    }
}
