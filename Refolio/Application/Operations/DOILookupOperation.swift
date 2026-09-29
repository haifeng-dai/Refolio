import Foundation

/// Lookup pipeline: normalize DOI → Crossref fetch → map DTO to ItemDraft.
/// Application layer is the only place that sees both Integrations DTOs and Domain drafts.
@MainActor
struct DOILookupOperation {
    private let client: any BibliographyClient

    init(client: any BibliographyClient) {
        self.client = client
    }

    func execute(rawDOI: String) async throws -> ItemDraft {
        let metadata = try await executeMetadata(rawDOI: rawDOI)
        return Self.draft(from: metadata, fallbackDOI: metadata.doi)
    }

    func executeMetadata(rawDOI: String) async throws -> DOIMetadata {
        guard let doi = DOIString.normalize(rawDOI) else {
            throw BibliographyClientError.invalidDOI
        }
        let envelope: CrossrefWorkEnvelope
        do {
            envelope = try await client.fetch(doi: doi)
        } catch let error as BibliographyClientError {
            throw error
        } catch {
            throw BibliographyClientError.network
        }
        return Self.metadata(from: envelope.message, fallbackDOI: doi)
    }

    static func metadata(from message: CrossrefWorkMessage, fallbackDOI: String) -> DOIMetadata {
        let title = message.title?.first?.trimmedOrNil

        let authors: [DOIAuthor]? = message.author?.compactMap { author in
            let givenName = author.given?.trimmedOrNil
            let familyName = author.family?.trimmedOrNil
            let literalName = author.name?.trimmedOrNil
            guard givenName != nil || familyName != nil || literalName != nil else {
                return nil
            }
            return DOIAuthor(
                givenName: givenName,
                familyName: familyName,
                literalName: literalName,
                orcid: author.ORCID?.trimmedOrNil
            )
        }

        let dateParts = message.issued?.dateParts?.first ?? []
        let year = dateParts.count > 0 ? dateParts[0] : nil
        let month = dateParts.count > 1 ? dateParts[1] : nil
        let day = dateParts.count > 2 ? dateParts[2] : nil

        let publicationTitle = message.containerTitle?.first?.trimmedOrNil
        let literatureType: String? = publicationTitle == nil
            ? nil
            : Self.literatureType(fromCrossrefType: message.type)

        let doi = message.DOI.flatMap(DOIString.normalize) ?? fallbackDOI

        return DOIMetadata(
            doi: doi,
            title: title,
            abstract: message.abstract.flatMap { Self.strippingMarkup($0).trimmedOrNil },
            publicationYear: year,
            publicationMonth: month,
            publicationDay: day,
            volume: message.volume?.trimmedOrNil,
            issue: message.issue?.trimmedOrNil,
            pageRange: message.page?.trimmedOrNil,
            urlString: message.URL?.trimmedOrNil,
            authors: authors,
            publicationTitle: publicationTitle,
            literatureType: literatureType
        )
    }

    static func draft(from metadata: DOIMetadata, fallbackDOI: String) -> ItemDraft {
        ItemDraft(
            title: metadata.title ?? "",
            abstract: metadata.abstract,
            doi: metadata.doi.isEmpty ? fallbackDOI : metadata.doi,
            publicationYear: metadata.publicationYear,
            publicationMonth: metadata.publicationMonth,
            publicationDay: metadata.publicationDay,
            volume: metadata.volume,
            issue: metadata.issue,
            pageRange: metadata.pageRange,
            urlString: metadata.urlString ?? "https://doi.org/\(metadata.doi)",
            publicationTitle: metadata.publicationTitle,
            literatureType: metadata.literatureType,
            authors: metadata.authors?.map {
                AuthorDraft(
                    givenName: $0.givenName,
                    familyName: $0.familyName,
                    literalName: $0.literalName,
                    orcid: $0.orcid
                )
            } ?? []
        )
    }

    private static func literatureType(fromCrossrefType type: String?) -> String {
        switch type {
        case "journal-article": "Journal article"
        case "proceedings-article", "conference-paper": "Conference paper"
        case "book": "Book"
        case "book-chapter": "Book chapter"
        case "posted-content", "article": "Preprint"
        case "dissertation", "thesis": "Thesis"
        case "report", "report-component": "Report"
        case "dataset": "Dataset"
        default: "Other"
        }
    }

    private static func strippingMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
