import Foundation

@MainActor
struct DOIUpdateOperation {
    func prepare(local: LibraryItem, remote: DOIMetadata) throws -> DOIUpdatePreview {
        guard let localDOI = local.doi.flatMap(DOIString.normalize),
              let remoteDOI = DOIString.normalize(remote.doi) else {
            throw DOIUpdateError.missingDOI
        }
        guard localDOI == remoteDOI else {
            throw DOIUpdateError.mismatchedDOI
        }

        return DOIUpdatePreview(
            itemID: local.id,
            local: local,
            remote: remote,
            changedFields: Self.changedFields(local: local, remote: remote)
        )
    }

    func mergedDraft(for plan: DOIUpdatePlan) throws -> ItemDraft {
        guard !plan.selectedFields.isEmpty else {
            throw DOIUpdateError.noChanges
        }

        let local = plan.local
        let remote = plan.remote
        let fields = plan.selectedFields
        let dateSelected = fields.contains(.publicationDate)
        let publicationSelected = fields.contains(.publication)

        return ItemDraft(
            title: fields.contains(.title) ? remote.title ?? local.title : local.title,
            abstract: fields.contains(.abstract) ? remote.abstract ?? local.abstract : local.abstract,
            doi: local.doi,
            publicationYear: dateSelected ? remote.publicationYear ?? local.publicationYear : local.publicationYear,
            publicationMonth: dateSelected ? remote.publicationMonth ?? local.publicationMonth : local.publicationMonth,
            publicationDay: dateSelected ? remote.publicationDay ?? local.publicationDay : local.publicationDay,
            volume: fields.contains(.volume) ? remote.volume ?? local.volume : local.volume,
            issue: fields.contains(.issue) ? remote.issue ?? local.issue : local.issue,
            pageRange: fields.contains(.pageRange) ? remote.pageRange ?? local.pageRange : local.pageRange,
            urlString: fields.contains(.url) ? remote.urlString ?? local.urlString : local.urlString,
            publicationTitle: publicationSelected
                ? remote.publicationTitle ?? local.publicationTitle
                : local.publicationTitle,
            literatureType: publicationSelected
                ? remote.literatureType ?? local.literatureType
                : local.literatureType,
            authors: fields.contains(.authors)
                ? remote.authors?.map(Self.authorDraft(from:)) ?? local.authors
                : local.authors
        )
    }

    static func changedFields(local: LibraryItem, remote: DOIMetadata) -> Set<DOIUpdateField> {
        var fields = Set<DOIUpdateField>()

        if let title = remote.title,
           normalized(title) != normalized(local.title) {
            fields.insert(.title)
        }

        if let abstract = remote.abstract,
           normalizedOptional(abstract) != normalizedOptional(local.abstract) {
            fields.insert(.abstract)
        }

        if (remote.publicationYear != nil && remote.publicationYear != local.publicationYear)
            || (remote.publicationMonth != nil && remote.publicationMonth != local.publicationMonth)
            || (remote.publicationDay != nil && remote.publicationDay != local.publicationDay) {
            fields.insert(.publicationDate)
        }

        if let volume = remote.volume,
           normalized(volume) != normalizedOptional(local.volume) {
            fields.insert(.volume)
        }

        if let issue = remote.issue,
           normalized(issue) != normalizedOptional(local.issue) {
            fields.insert(.issue)
        }

        if let pageRange = remote.pageRange,
           normalized(pageRange) != normalizedOptional(local.pageRange) {
            fields.insert(.pageRange)
        }

        if let urlString = remote.urlString,
           normalized(urlString) != normalizedOptional(local.urlString) {
            fields.insert(.url)
        }

        if let authors = remote.authors,
           authors.map(Self.authorDraft(from:)) != local.authors {
            fields.insert(.authors)
        }

        if remote.publicationTitle != nil || remote.literatureType != nil {
            let titleChanged = remote.publicationTitle.map {
                normalized($0) != normalizedOptional(local.publicationTitle)
            } ?? false
            let typeChanged = remote.literatureType.map {
                normalized($0) != normalizedOptional(local.literatureType)
            } ?? false
            if titleChanged || typeChanged {
                fields.insert(.publication)
            }
        }

        return fields
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func authorDraft(from author: DOIAuthor) -> AuthorDraft {
        let draft = AuthorDraft(
            givenName: author.givenName,
            familyName: author.familyName,
            literalName: author.literalName,
            orcid: author.orcid
        )
        return draft.normalized() ?? draft
    }

    private static func normalizedOptional(_ value: String?) -> String {
        normalized(value ?? "")
    }
}
