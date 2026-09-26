import Foundation

/// 小牛翻译的纯 API 引擎。
///
/// 运行时只需要 API Key，不依赖小牛网页登录、Cookie 或账号密码。
public struct NiuTransTranslationEngine: TranslationEngine {
    public let id = "niutrans"
    public let displayName = "NiuTrans"
    public let requiresAPIKey: Bool = true

    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    public init(
        apiKey: String,
        endpoint: URL = URL(string: "https://niutrans.com/niuInterface")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.session = session
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NiuTransTranslationEngineError.emptyText
        }
        guard !apiKey.isEmpty else {
            throw NiuTransTranslationEngineError.missingAPIKey
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw NiuTransTranslationEngineError.invalidURL
        }
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = path + "/textTranslation"
        components.queryItems = [
            URLQueryItem(name: "pluginType", value: "zotero"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components.url else {
            throw NiuTransTranslationEngineError.invalidURL
        }

        let sourceLanguage = languageCode(for: request.sourceLanguage, automaticCode: "auto")
        let targetLanguage = languageCode(for: request.targetLanguage, automaticCode: "zh")
        let body = NiuTransRequest(
            from: sourceLanguage,
            to: targetLanguage,
            realmCode: 99,
            source: "refolio",
            text: text
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Refolio/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw NiuTransTranslationEngineError.invalidRequest
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NiuTransTranslationEngineError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NiuTransTranslationEngineError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw NiuTransTranslationEngineError.httpStatus(httpResponse.statusCode)
        }

        let payload: NiuTransResponse
        do {
            payload = try JSONDecoder().decode(NiuTransResponse.self, from: data)
        } catch {
            throw NiuTransTranslationEngineError.invalidResponse
        }

        if let errorCode = payload.errorCode {
            throw NiuTransTranslationEngineError.service(code: errorCode, message: payload.errorMessage)
        }
        if let code = payload.code, code != 200 {
            throw NiuTransTranslationEngineError.service(code: code, message: payload.message)
        }

        let translatedText = payload.data?.translatedText ?? payload.translatedText
        guard let translatedText, !translatedText.isEmpty else {
            throw NiuTransTranslationEngineError.emptyResult
        }

        return TranslationResult(text: translatedText)
    }

    private func languageCode(for language: String?, automaticCode: String) -> String {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else {
            return automaticCode
        }

        switch language.lowercased() {
        case "zh-hans", "zh-cn", "zh-sg":
            return "zh"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo":
            return "cht"
        default:
            return language.split(separator: "-").first.map(String.init) ?? language
        }
    }
}

public enum NiuTransTranslationEngineError: LocalizedError, Sendable {
    case emptyText
    case missingAPIKey
    case invalidRequest
    case invalidURL
    case network(String)
    case httpStatus(Int)
    case service(code: Int, message: String?)
    case invalidResponse
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "There is no text to translate."
        case .missingAPIKey:
            return "NiuTrans API Key is not configured."
        case .invalidRequest:
            return "The NiuTrans request could not be encoded."
        case .invalidURL:
            return "The NiuTrans request URL is invalid."
        case .network(let message):
            return "NiuTrans translation failed: \(message)"
        case .httpStatus(let statusCode):
            return "NiuTrans returned HTTP \(statusCode)."
        case .service(let code, let message):
            if let message, !message.isEmpty {
                return "NiuTrans returned error \(code): \(message)"
            }
            return "NiuTrans returned error \(code)."
        case .invalidResponse:
            return "NiuTrans returned an unexpected response."
        case .emptyResult:
            return "NiuTrans returned no translated text."
        }
    }
}

private struct NiuTransRequest: Encodable {
    let from: String
    let to: String
    let realmCode: Int
    let source: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case from
        case to
        case realmCode
        case source
        case text = "src_text"
    }
}

private struct NiuTransResponse: Decodable {
    let code: Int?
    let message: String?
    let data: DataPayload?
    let translatedText: String?
    let errorCode: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message = "msg"
        case data
        case translatedText = "tgt_text"
        case errorCode = "error_code"
        case errorMessage = "error_msg"
    }

    struct DataPayload: Decodable {
        let translatedText: String?

        enum CodingKeys: String, CodingKey {
            case translatedText = "tgt_text"
        }
    }
}
