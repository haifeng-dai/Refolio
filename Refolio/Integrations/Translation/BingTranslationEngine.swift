import Foundation

public struct BingTranslationEngine: TranslationEngine {
    public let id = "bing"
    public let displayName = "Bing"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw BingTranslationEngineError.emptyText
        }

        guard var components = URLComponents(string: "https://edge.microsoft.com/translate/translatetext") else {
            throw BingTranslationEngineError.invalidURL
        }

        let sourceLanguage: String
        if let requestedSource = request.sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedSource.isEmpty {
            sourceLanguage = requestedSource
        } else {
            sourceLanguage = ""
        }
        components.queryItems = [
            // Bing 的免费 Edge 接口通过空的 from 参数触发自动检测，不能填写 auto-detect。
            URLQueryItem(name: "from", value: sourceLanguage),
            URLQueryItem(name: "to", value: request.targetLanguage),
            URLQueryItem(name: "isEnterpriseClient", value: "false")
        ]

        guard let url = components.url else {
            throw BingTranslationEngineError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Refolio/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15
        do {
            urlRequest.httpBody = try JSONEncoder().encode([text])
        } catch {
            throw BingTranslationEngineError.invalidRequest
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw BingTranslationEngineError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BingTranslationEngineError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BingTranslationEngineError.httpStatus(httpResponse.statusCode)
        }

        let payload: [BingResponse]
        do {
            payload = try JSONDecoder().decode([BingResponse].self, from: data)
        } catch {
            throw BingTranslationEngineError.invalidResponse
        }

        guard let firstResponse = payload.first,
              let translation = firstResponse.translations.first,
              !translation.text.isEmpty else {
            throw BingTranslationEngineError.emptyResult
        }

        return TranslationResult(
            text: translation.text,
            detectedSourceLanguage: firstResponse.detectedLanguage?.language
        )
    }
}

public enum BingTranslationEngineError: LocalizedError, Sendable {
    case emptyText
    case invalidRequest
    case invalidURL
    case network(String)
    case httpStatus(Int)
    case invalidResponse
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "There is no text to translate."
        case .invalidRequest:
            return "The translation request could not be encoded."
        case .invalidURL:
            return "The translation request URL is invalid."
        case .network(let message):
            return "Bing translation failed: \(message)"
        case .httpStatus(let statusCode):
            return "Bing translation returned HTTP \(statusCode)."
        case .invalidResponse:
            return "Bing returned an unexpected translation response."
        case .emptyResult:
            return "Bing returned no translated text."
        }
    }
}

private struct BingResponse: Decodable, Sendable {
    let detectedLanguage: DetectedLanguage?
    let translations: [BingTranslation]

    struct DetectedLanguage: Decodable, Sendable {
        let language: String?
    }

    struct BingTranslation: Decodable, Sendable {
        let text: String
        let to: String?
    }
}
