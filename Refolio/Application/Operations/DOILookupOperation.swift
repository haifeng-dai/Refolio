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
        return Self.draft(from: envelope.message, fallbackDOI: doi)
    }

    static func draft(from message: CrossrefWorkMessage, fallbackDOI: String) -> ItemDraft {
        let title = message.title?.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let authors: [String] = (message.author ?? []).map { author in
            if let family = author.family?.trimmedOrNil {
                if let given = author.given?.trimmedOrNil {
                    return "\(family), \(given)"
                }
                return family
            }
            return author.name?.trimmedOrNil ?? ""
        }
        .filter { !$0.isEmpty }

        let dateParts = message.issued?.dateParts?.first ?? []
        let year = dateParts.count > 0 ? dateParts[0] : nil
        let month = dateParts.count > 1 ? dateParts[1] : nil
        let day = dateParts.count > 2 ? dateParts[2] : nil

        let publicationTitle = message.containerTitle?.first?.trimmedOrNil
        let literatureType: String? = publicationTitle == nil
            ? nil
            : Self.literatureType(fromCrossrefType: message.type)

        let doi = message.DOI.flatMap(DOIString.normalize) ?? fallbackDOI

        return ItemDraft(
            title: title ?? "",
            abstract: message.abstract.map(Self.strippingMarkup),
            doi: doi,
            publicationYear: year,
            publicationMonth: month,
            publicationDay: day,
            volume: message.volume?.trimmedOrNil,
            issue: message.issue?.trimmedOrNil,
            pageRange: message.page?.trimmedOrNil,
            urlString: message.URL?.trimmedOrNil ?? "https://doi.org/\(doi)",
            authorNames: authors,
            publicationTitle: publicationTitle,
            literatureType: literatureType
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
