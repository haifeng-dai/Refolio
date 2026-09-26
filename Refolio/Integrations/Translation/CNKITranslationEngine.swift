import Foundation

public struct CNKITranslationEngine: TranslationEngine {
    public let id = "cnki"
    public let displayName = "CNKI"

    private let session: URLSession
    private let tokenCache: CNKITokenCache

    public init(session: URLSession = .shared) {
        self.session = session
        self.tokenCache = CNKITokenCache()
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CNKITranslationEngineError.emptyText
        }
        guard text.count <= 800 else {
            throw CNKITranslationEngineError.textTooLong(maximum: 800)
        }

        let token = try await tokenCache.value(using: session)
        let words: String
        do {
            words = try TranslationCrypto.aesECBPKCS7Base64URL(text, key: "4e87183cfd3a45fe")
        } catch {
            throw CNKITranslationEngineError.encryptionFailed
        }

        let payload = CNKIRequest(words: words)
        var urlRequest = URLRequest(url: URL(string: "https://dict.cnki.net/fyzs-front-api/translate/literaltranslation")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(token, forHTTPHeaderField: "Token")
        urlRequest.setValue("Refolio/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15
        do {
            urlRequest.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw CNKITranslationEngineError.invalidRequest
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw CNKITranslationEngineError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CNKITranslationEngineError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CNKITranslationEngineError.httpStatus(httpResponse.statusCode)
        }

        let decoded: CNKIResponse
        do {
            decoded = try JSONDecoder().decode(CNKIResponse.self, from: data)
        } catch {
            throw CNKITranslationEngineError.invalidResponse
        }
        if decoded.data?.isInputVerificationCode == true {
            throw CNKITranslationEngineError.verificationRequired
        }
        guard let result = decoded.data?.result?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            throw CNKITranslationEngineError.emptyResult
        }
        return TranslationResult(text: result)
    }
}

private actor CNKITokenCache {
    private var token: String?
    private var expiresAt: Date?

    func value(using session: URLSession) async throws -> String {
        if let token, let expiresAt, expiresAt > Date() {
            return token
        }

        var request = URLRequest(url: URL(string: "https://dict.cnki.net/fyzs-front-api/getToken")!)
        request.httpMethod = "GET"
        request.setValue("Refolio/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CNKITranslationEngineError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CNKITranslationEngineError.invalidResponse
        }
        let payload: CNKITokenResponse
        do {
            payload = try JSONDecoder().decode(CNKITokenResponse.self, from: data)
        } catch {
            throw CNKITranslationEngineError.invalidResponse
        }
        guard payload.code == 200, let token = payload.data, !token.isEmpty else {
            throw CNKITranslationEngineError.tokenUnavailable
        }
        self.token = token
        self.expiresAt = Date().addingTimeInterval(240)
        return token
    }
}

private struct CNKIRequest: Encodable {
    let words: String
    let translateType: String? = nil
}

private struct CNKITokenResponse: Decodable {
    let code: Int
    let data: String?
}

private struct CNKIResponse: Decodable {
    let data: DataPayload?

    struct DataPayload: Decodable {
        let result: String?
        let isInputVerificationCode: Bool?

        enum CodingKeys: String, CodingKey {
            case result = "mResult"
            case isInputVerificationCode
        }
    }
}

public enum CNKITranslationEngineError: LocalizedError, Sendable {
    case emptyText
    case textTooLong(maximum: Int)
    case encryptionFailed
    case invalidRequest
    case network(String)
    case httpStatus(Int)
    case invalidResponse
    case tokenUnavailable
    case verificationRequired
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyText: "There is no text to translate."
        case .textTooLong(let maximum): "CNKI accepts at most \(maximum) characters per request."
        case .encryptionFailed: "CNKI request encryption failed."
        case .invalidRequest: "The CNKI request could not be encoded."
        case .network(let message): "CNKI translation failed: \(message)"
        case .httpStatus(let code): "CNKI returned HTTP \(code)."
        case .invalidResponse: "CNKI returned an unexpected response."
        case .tokenUnavailable: "CNKI did not provide a translation token."
        case .verificationRequired: "CNKI requires browser verification before translating again."
        case .emptyResult: "CNKI returned no translated text."
        }
    }
}
