import Foundation

public struct GoogleTranslationEngine: TranslationEngine {
    public let id: String
    public let displayName: String

    private let endpoint: URL
    private let session: URLSession

    public init(
        id: String = "google",
        displayName: String = "Google",
        endpoint: URL = URL(string: "https://translate.google.com")!,
        session: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.session = session
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw GoogleTranslationEngineError.emptyText
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw GoogleTranslationEngineError.invalidURL
        }
        components.path = "/translate_a/single"
        let source = languageCode(request.sourceLanguage, automatic: "auto")
        let target = languageCode(request.targetLanguage, automatic: "zh-CN")
        let queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "dt", value: "at"),
            URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "source", value: "bh"),
            URLQueryItem(name: "ssel", value: "0"),
            URLQueryItem(name: "tsel", value: "0"),
            URLQueryItem(name: "kc", value: "1"),
            URLQueryItem(name: "tk", value: token(for: text)),
            URLQueryItem(name: "q", value: text)
        ]
        components.queryItems = queryItems

        guard let url = components.url else {
            throw GoogleTranslationEngineError.invalidURL
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
            throw GoogleTranslationEngineError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleTranslationEngineError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GoogleTranslationEngineError.httpStatus(httpResponse.statusCode)
        }

        let translatedText = parseTranslation(from: data)
        guard !translatedText.isEmpty else {
            throw GoogleTranslationEngineError.emptyResult
        }
        return TranslationResult(text: translatedText)
    }

    private func languageCode(_ language: String?, automatic: String) -> String {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else {
            return automatic
        }
        if language.lowercased() == "zh-hans" { return "zh-CN" }
        if language.lowercased() == "zh-hant" { return "zh-TW" }
        if language.lowercased() == "pt-br" { return "pt" }
        return language
    }

    private func token(for text: String) -> String {
        var value: UInt32 = 406_644
        for byte in text.utf8 {
            value = value &+ UInt32(byte)
            value = mix(value, pattern: "+-a^+6")
        }
        value = mix(value, pattern: "+-3^+b+-f")
        value ^= 3_293_161_072
        let first = value % 1_000_000
        let second = Int32(bitPattern: first ^ 406_644)
        return "\(first).\(second)"
    }

    private func mix(_ value: UInt32, pattern: String) -> UInt32 {
        let chars = Array(pattern)
        var result = value
        var index = 0
        while index + 2 < chars.count {
            let shiftCharacter = chars[index + 2]
            let shift: UInt32
            if let ascii = shiftCharacter.asciiValue, ascii >= 97 {
                shift = UInt32(ascii - 87)
            } else {
                shift = UInt32(shiftCharacter.wholeNumberValue ?? 0)
            }
            let shifted = chars[index + 1] == "+" ? result >> shift : result << shift
            result = chars[index] == "+" ? result &+ shifted : result ^ shifted
            index += 3
        }
        return result
    }

    private func parseTranslation(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            return ""
        }
        return segments.compactMap { segment in
            (segment as? [Any])?.first as? String
        }.joined()
    }
}

public enum GoogleTranslationEngineError: LocalizedError, Sendable {
    case emptyText
    case invalidURL
    case network(String)
    case httpStatus(Int)
    case invalidResponse
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyText: "There is no text to translate."
        case .invalidURL: "The Google translation URL is invalid."
        case .network(let message): "Google translation failed: \(message)"
        case .httpStatus(let code): "Google returned HTTP \(code)."
        case .invalidResponse: "Google returned an unexpected response."
        case .emptyResult: "Google returned no translated text."
        }
    }
}
