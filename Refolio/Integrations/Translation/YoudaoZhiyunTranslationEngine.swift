import Foundation

public struct YoudaoZhiyunTranslationEngine: TranslationEngine {
    public let id = "youdaozhiyun"
    public let displayName = "Youdao Zhiyun"
    public let requiresAPIKey = true

    private let credentials: String
    private let domain: String
    private let session: URLSession

    public init(
        credentials: String,
        domain: String = "general",
        session: URLSession = .shared
    ) {
        self.credentials = credentials.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain
        self.session = session
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw YoudaoZhiyunTranslationEngineError.emptyText
        }
        let parts = credentials.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw YoudaoZhiyunTranslationEngineError.invalidCredentials
        }

        let appKey = parts[0]
        let appSecret = parts[1]
        let vocabID = parts.count > 2 ? parts[2] : ""
        let salt = String(Int(Date().timeIntervalSince1970 * 1000))
        let currentTime = String(Int(Date().timeIntervalSince1970))
        let signSource = appKey + truncate(text) + salt + currentTime + appSecret
        let sign = TranslationCrypto.sha256Hex(signSource)

        guard var components = URLComponents(string: "https://openapi.youdao.com/api") else {
            throw YoudaoZhiyunTranslationEngineError.invalidURL
        }
        var queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "appKey", value: appKey),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "from", value: languageCode(request.sourceLanguage, automatic: "auto")),
            URLQueryItem(name: "to", value: languageCode(request.targetLanguage, automatic: "zh-CHS")),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: currentTime),
            URLQueryItem(name: "domain", value: domain)
        ]
        if !vocabID.isEmpty {
            queryItems.append(URLQueryItem(name: "vocabId", value: vocabID))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw YoudaoZhiyunTranslationEngineError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Refolio/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw YoudaoZhiyunTranslationEngineError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YoudaoZhiyunTranslationEngineError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw YoudaoZhiyunTranslationEngineError.httpStatus(httpResponse.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YoudaoZhiyunTranslationEngineError.invalidResponse
        }
        let errorCode = stringValue(object["errorCode"]) ?? "0"
        guard errorCode == "0" else {
            throw YoudaoZhiyunTranslationEngineError.service(code: errorCode, message: stringValue(object["errorMsg"]))
        }
        let translated = (object["translation"] as? [String])?.joined() ?? ""
        guard !translated.isEmpty else {
            throw YoudaoZhiyunTranslationEngineError.emptyResult
        }
        return TranslationResult(text: translated)
    }

    private func truncate(_ value: String) -> String {
        guard value.count > 20 else { return value }
        let prefix = String(value.prefix(10))
        let suffix = String(value.suffix(10))
        return prefix + String(value.count) + suffix
    }

    private func languageCode(_ language: String?, automatic: String) -> String {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else { return automatic }
        switch language.lowercased() {
        case "zh-hans", "zh-cn", "zh-sg": return "zh-CHS"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo": return "zh-CHT"
        default: return language
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Int { return String(value) }
        return nil
    }
}

public enum YoudaoZhiyunTranslationEngineError: LocalizedError, Sendable {
    case emptyText
    case invalidCredentials
    case invalidURL
    case network(String)
    case httpStatus(Int)
    case service(code: String, message: String?)
    case invalidResponse
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyText: return "There is no text to translate."
        case .invalidCredentials: return "Youdao credentials must use AppID#AppKey."
        case .invalidURL: return "The Youdao translation URL is invalid."
        case .network(let message): return "Youdao translation failed: \(message)"
        case .httpStatus(let code): return "Youdao returned HTTP \(code)."
        case .service(let code, let message):
            if let message, !message.isEmpty { return "Youdao returned error \(code): \(message)" }
            return "Youdao returned error \(code)."
        case .invalidResponse: return "Youdao returned an unexpected response."
        case .emptyResult: return "Youdao returned no translated text."
        }
    }
}
