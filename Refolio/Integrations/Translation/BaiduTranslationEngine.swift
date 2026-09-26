import Foundation

public struct BaiduTranslationEngine: TranslationEngine {
    public let id = "baidu"
    public let displayName = "Baidu"
    public let requiresAPIKey = true

    private let credentials: String
    private let session: URLSession

    public init(credentials: String, session: URLSession = .shared) {
        self.credentials = credentials.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw BaiduTranslationEngineError.emptyText
        }
        let parts = credentials.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw BaiduTranslationEngineError.invalidCredentials
        }

        let appID = parts[0]
        let key = parts[1]
        let action = parts.count > 2 && !parts[2].isEmpty ? parts[2] : "0"
        let salt = String(Int(Date().timeIntervalSince1970 * 1000))
        let sign = TranslationCrypto.md5Hex(appID + text + salt + key)

        guard var components = URLComponents(string: "https://api.fanyi.baidu.com/api/trans/vip/translate") else {
            throw BaiduTranslationEngineError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "from", value: languageCode(request.sourceLanguage, automatic: "auto")),
            URLQueryItem(name: "to", value: languageCode(request.targetLanguage, automatic: "zh")),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "needIntervene", value: "1")
        ]
        guard let url = components.url else {
            throw BaiduTranslationEngineError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Refolio/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw BaiduTranslationEngineError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BaiduTranslationEngineError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw BaiduTranslationEngineError.httpStatus(httpResponse.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BaiduTranslationEngineError.invalidResponse
        }
        if let errorCode = stringValue(object["error_code"]) {
            throw BaiduTranslationEngineError.service(code: errorCode, message: stringValue(object["error_msg"]))
        }
        let translated = (object["trans_result"] as? [[String: Any]])?
            .compactMap { $0["dst"] as? String }
            .joined() ?? ""
        guard !translated.isEmpty else {
            throw BaiduTranslationEngineError.emptyResult
        }
        return TranslationResult(text: translated)
    }

    private func languageCode(_ language: String?, automatic: String) -> String {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else { return automatic }
        switch language.lowercased() {
        case "zh-hans", "zh-cn", "zh-sg": return "zh"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo": return "cht"
        default: return language.split(separator: "-").first.map(String.init) ?? language
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Int { return String(value) }
        return nil
    }
}

public enum BaiduTranslationEngineError: LocalizedError, Sendable {
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
        case .invalidCredentials: return "Baidu credentials must use AppID#Key."
        case .invalidURL: return "The Baidu translation URL is invalid."
        case .network(let message): return "Baidu translation failed: \(message)"
        case .httpStatus(let code): return "Baidu returned HTTP \(code)."
        case .service(let code, let message):
            if let message, !message.isEmpty { return "Baidu returned error \(code): \(message)" }
            return "Baidu returned error \(code)."
        case .invalidResponse: return "Baidu returned an unexpected response."
        case .emptyResult: return "Baidu returned no translated text."
        }
    }
}
