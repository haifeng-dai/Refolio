import Foundation

enum BibliographyClientError: LocalizedError {
    case invalidDOI
    case notFound
    case network
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidDOI: "Enter a valid DOI such as 10.1234/example."
        case .notFound: "No Crossref record was found for this DOI."
        case .network: "The network request failed. Check your connection and try again."
        case .invalidResponse: "Crossref returned an unexpected response."
        }
    }
}

protocol BibliographyClient: Sendable {
    func fetch(doi: String) async throws -> CrossrefWorkEnvelope
}

/// HTTP + JSON only. Does not import Domain types.
struct CrossrefClient: BibliographyClient {
    static let baseURL = URL(string: "https://api.crossref.org/works/")!

    var session: URLSession = .shared
    /// Crossref polite pool: identify the app and a contact.
    var userAgent: String = "Refolio/1.0 (mailto:refolio@example.com)"

    func fetch(doi: String) async throws -> CrossrefWorkEnvelope {
        let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        guard let url = URL(string: encoded, relativeTo: Self.baseURL) else {
            throw BibliographyClientError.invalidDOI
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BibliographyClientError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw BibliographyClientError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw BibliographyClientError.notFound
        default:
            throw BibliographyClientError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(CrossrefWorkEnvelope.self, from: data)
        } catch {
            throw BibliographyClientError.invalidResponse
        }
    }
}
