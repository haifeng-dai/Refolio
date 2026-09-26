import AppKit
import Foundation
import SwiftUI

// MARK: - Mock Translation Engine

public final class MockTranslationEngine: TranslationEngine {
    public let id = "mock"
    public let displayName = "Mock"

    public init() {}

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        // 模拟 150ms 网络请求延迟，测试加载状态与动画
        try await Task.sleep(nanoseconds: 150_000_000)
        // 用户要求：“后段的查询功能先原文返回即可”
        return TranslationResult(text: request.text)
    }
}

// MARK: - Supported Target Languages

public struct TranslationLanguage: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let code: String

    public static let supported: [TranslationLanguage] = [
        TranslationLanguage(id: "zh-Hans", name: "简体中文", code: "zh-Hans"),
        TranslationLanguage(id: "en", name: "English", code: "en"),
        TranslationLanguage(id: "zh-Hant", name: "繁體中文", code: "zh-Hant"),
        TranslationLanguage(id: "ja", name: "日本語", code: "ja"),
        TranslationLanguage(id: "fr", name: "Français", code: "fr"),
        TranslationLanguage(id: "de", name: "Deutsch", code: "de"),
        TranslationLanguage(id: "es", name: "Español", code: "es")
    ]
}

// MARK: - Translation History Record

public struct TranslationRecord: Identifiable, Hashable {
    public let id = UUID()
    public let original: String
    public let translated: String
    public let targetLanguage: String
    public let timestamp: Date

    public init(original: String, translated: String, targetLanguage: String, timestamp: Date = Date()) {
        self.original = original
        self.translated = translated
        self.targetLanguage = targetLanguage
        self.timestamp = timestamp
    }
}

// MARK: - PDF Academic Text Normalizer

/// 针对学术论文 PDF 常见的两栏排版断行、连字符硬回车进行自动段落清洗
public func normalizePDFText(_ rawText: String) -> String {
    var text = rawText
    // 移除软连字符
    text = text.replacingOccurrences(of: "\u{00AD}", with: "")

    // 修复单词换行连字符：word-\nword -> wordword
    text = text.replacingOccurrences(
        of: "([a-zA-Z])-[\r\n]+\\s*([a-zA-Z])",
        with: "$1$2",
        options: .regularExpression
    )

    // 将两个及以上连续换行视为自然段落，单换行视为空格断行
    let paragraphs = text.components(separatedBy: "\n\n")
    let cleanedParagraphs = paragraphs.compactMap { paragraph -> String? in
        let cleaned = paragraph
            .replacingOccurrences(of: "[\r\n]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    return cleanedParagraphs.joined(separator: "\n\n")
}

// MARK: - Translation View Model

@Observable
@MainActor
public final class TranslationViewModel {
    public var originalText: String = ""
    public var translatedText: String = ""
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    public var targetLanguage: String = "zh-Hans"
    public var isAutoTranslateEnabled: Bool = true
    public var isFloatingPopoverEnabled: Bool = true

    // 悬浮气泡状态与锚点位置（在 PDFView 坐标系中）
    public var isShowingFloatingPopover: Bool = false
    public var popoverAnchorRect: CGRect = .zero

    // 历史记录
    public var history: [TranslationRecord] = []

    private let engine: any TranslationEngine
    private var debounceTask: Task<Void, Never>?

    public init(engine: any TranslationEngine = TranslationEngineRegistry.builtIn.defaultEngine) {
        self.engine = engine
    }

    /// 当 PDF 中的划选文字发生变化时调用
    public func handleSelectionChange(rawText: String?, anchorRect: CGRect?) {
        guard let rawText else {
            // 取消选区时，不立即隐藏侧边栏的翻译，但如果气泡开启且点空白，可处理气泡
            return
        }

        let cleaned = normalizePDFText(rawText)
        guard !cleaned.isEmpty, cleaned.count > 1 else { return }

        // 如果用户选中文本变了，才更新并触发翻译
        let textChanged = (cleaned != originalText)
        originalText = cleaned

        if let rect = anchorRect, isFloatingPopoverEnabled {
            popoverAnchorRect = rect
            withAnimation(.easeOut(duration: 0.15)) {
                isShowingFloatingPopover = true
            }
        }

        if isAutoTranslateEnabled && textChanged {
            requestTranslation(text: cleaned)
        }
    }

    /// 发起翻译请求
    public func requestTranslation(text: String? = nil) {
        let textToTranslate = text ?? originalText
        guard !textToTranslate.isEmpty else { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            // 200ms 防抖，等待划词选择完成
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }

            self.isLoading = true
            self.errorMessage = nil

            do {
                let result = try await self.engine.translate(
                    TranslationRequest(
                        text: textToTranslate,
                        sourceLanguage: nil,
                        targetLanguage: self.targetLanguage
                    )
                )
                guard !Task.isCancelled else { return }
                self.translatedText = result.text
                self.isLoading = false

                // 记录到历史
                if !self.history.contains(where: { $0.original == textToTranslate && $0.targetLanguage == self.targetLanguage }) {
                    let record = TranslationRecord(
                        original: textToTranslate,
                        translated: result.text,
                        targetLanguage: self.targetLanguage,
                        timestamp: Date()
                    )
                    self.history.insert(record, at: 0)
                    if self.history.count > 40 {
                        self.history.removeLast()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// 重新翻译当前文本（如切换语言后）
    public func retranslate() {
        requestTranslation(text: originalText)
    }

    /// 复制翻译结果到剪贴板
    public func copyTranslation() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }

    /// 复制原文到剪贴板
    public func copyOriginal() {
        guard !originalText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(originalText, forType: .string)
    }

    /// 关闭悬浮气泡
    public func dismissFloatingPopover() {
        withAnimation(.easeIn(duration: 0.12)) {
            isShowingFloatingPopover = false
        }
    }

    /// 清空当前翻译和选中文本
    public func clearCurrent() {
        debounceTask?.cancel()
        originalText = ""
        translatedText = ""
        errorMessage = nil
        dismissFloatingPopover()
    }

    /// 清空所有历史记录
    public func clearHistory() {
        history.removeAll()
    }
}
