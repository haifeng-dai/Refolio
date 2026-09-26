import Foundation

/// 一个翻译引擎请求。引擎只接收翻译所需的数据，不依赖具体的网络服务。
public struct TranslationRequest: Sendable, Equatable {
    public let text: String
    public let sourceLanguage: String?
    public let targetLanguage: String

    public init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

/// 翻译引擎的统一返回值。检测出的源语言由支持该能力的引擎提供。
public struct TranslationResult: Sendable, Equatable {
    public let text: String
    public let detectedSourceLanguage: String?

    public init(text: String, detectedSourceLanguage: String? = nil) {
        self.text = text
        self.detectedSourceLanguage = detectedSourceLanguage
    }
}

/// 每个具体翻译引擎都实现这组最小能力。
///
/// 引擎的认证、请求地址、响应格式和其他配置属于各自实现，避免把某一个供应商
/// 的字段扩散到公共接口中。
public protocol TranslationEngine: Sendable {
    var id: String { get }
    var displayName: String { get }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

/// 应用层的引擎目录。以后新增引擎时，只需把新的实现加入目录即可。
public struct TranslationEngineRegistry: Sendable {
    public let engines: [any TranslationEngine]
    public let defaultEngineID: String

    public init(
        engines: [any TranslationEngine],
        defaultEngineID: String? = nil
    ) {
        precondition(!engines.isEmpty, "TranslationEngineRegistry requires at least one engine")

        let ids = engines.map(\.id)
        precondition(Set(ids).count == ids.count, "Translation engine IDs must be unique")

        self.engines = engines
        self.defaultEngineID = defaultEngineID ?? engines[0].id
        precondition(ids.contains(self.defaultEngineID), "The default translation engine must be registered")
    }

    public var defaultEngine: any TranslationEngine {
        engine(withID: defaultEngineID)!
    }

    public func engine(withID id: String) -> (any TranslationEngine)? {
        engines.first { $0.id == id }
    }

    /// 当前已内置的引擎。后续引擎会在这里集中注册，不改变公共协议。
    public static let builtIn = TranslationEngineRegistry(
        engines: [BingTranslationEngine()],
        defaultEngineID: "bing"
    )
}
