import AppKit
import SwiftUI

// MARK: - Translation Workstation (Right Sidebar Detail Panel)

struct TranslationWorkstationView: View {
    @Bindable var viewModel: TranslationViewModel
    let onOpenDetailColumn: (() -> Void)?

    @State private var isShowingSettingsSheet: Bool = false
    @State private var isOriginalExpanded: Bool = true

    init(viewModel: TranslationViewModel, onOpenDetailColumn: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenDetailColumn = onOpenDetailColumn
    }

    var body: some View {
        VStack(spacing: 14) {
            headerBar

            if viewModel.originalText.isEmpty {
                emptyPlaceholder
            } else {
                contentSections
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .sheet(isPresented: $isShowingSettingsSheet) {
            TranslationSettingsSheet(viewModel: viewModel)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            // 目标语言选择
            Menu {
                ForEach(TranslationLanguage.supported) { lang in
                    Button {
                        viewModel.targetLanguage = lang.code
                        viewModel.retranslate()
                    } label: {
                        HStack {
                            Text(lang.name)
                            if viewModel.targetLanguage == lang.code {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(selectedLanguageName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // 翻译引擎选择
            Menu {
                ForEach(viewModel.availableEngines, id: \.id) { engine in
                    Button {
                        viewModel.selectedEngineID = engine.id
                    } label: {
                        HStack {
                            Text(engine.displayName)
                            if viewModel.selectedEngineID == engine.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(viewModel.currentEngine.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Menu {
                Toggle("划词自动翻译", isOn: $viewModel.isAutoTranslateEnabled)
                Toggle("显示悬浮气泡", isOn: $viewModel.isFloatingPopoverEnabled)
                Divider()
                if viewModel.currentEngine.requiresAPIKey {
                    Button {
                        isShowingSettingsSheet = true
                    } label: {
                        Label("配置 \(viewModel.currentEngine.displayName) API Key…", systemImage: "key.fill")
                    }
                    Divider()
                }
                Button("清空翻译缓存") {
                    viewModel.clearCache()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("翻译设置")
        }
    }

    private var selectedLanguageName: String {
        TranslationLanguage.supported.first(where: { $0.code == viewModel.targetLanguage })?.name ?? "目标语言"
    }

    // MARK: - Empty Placeholder

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.bubble")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
                .padding(.top, 30)

            Text("在 PDF 中划词即可自动翻译")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("支持自动识别双栏换行排版，拼接连字符与长难句。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Content Sections

    private var contentSections: some View {
        VStack(spacing: 14) {
            originalCard
            translatedCard
        }
    }

    // MARK: - Original Text Card

    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text("原文")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.originalText.count) 字符")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isOriginalExpanded.toggle()
                    }
                }
                .help(isOriginalExpanded ? "点击收起原文" : "点击展开原文")

                Spacer()

                Button {
                    viewModel.copyOriginal()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("复制原文")

                Button {
                    viewModel.clearCurrent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("清除当前内容")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isOriginalExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isOriginalExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isOriginalExpanded ? "收起原文" : "展开原文")
            }

            if isOriginalExpanded {
                Text(viewModel.originalText)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Translated Text Card

    private var translatedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("译文")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Spacer()

                if !viewModel.translatedText.isEmpty {
                    Button {
                        viewModel.copyTranslation()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("复制译文")
                }

                Button {
                    viewModel.retranslate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("重新请求翻译")
                .disabled(viewModel.isLoading)
            }

            if let error = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("翻译失败: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)

                    HStack(spacing: 8) {
                        Button("重试") {
                            viewModel.retranslate()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if error.contains("API Key") {
                            Button("配置 API Key") {
                                isShowingSettingsSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            } else if viewModel.isLoading && viewModel.translatedText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在翻译中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                Text(viewModel.translatedText.isEmpty ? "等待翻译…" : viewModel.translatedText)
                    .font(.system(size: 13.5, weight: .regular))
                    .lineSpacing(3.5)
                    .foregroundStyle(viewModel.translatedText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Floating Popover (Overlay directly near selection)

struct TranslationFloatingPopover: View {
    @Bindable var viewModel: TranslationViewModel
    let onOpenDetailPanel: () -> Void
    var onClose: (() -> Void)? = nil
    var onHighlight: (() -> String?)? = nil
    var onContentSizeChange: (() -> Void)? = nil

    @State private var isCopied: Bool = false
    @State private var highlightMessage: String?
    @State private var highlightFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部导航栏
            HStack(spacing: 6) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                Text("翻译")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    viewModel.copyTranslation()
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isCopied = false
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(isCopied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isCopied ? "已复制" : "复制译文")

                Button {
                    onOpenDetailPanel()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("在侧边栏完整查看")

                Button {
                    onClose?()
                    viewModel.dismissFloatingPopover()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭气泡")
            }

            Divider()

            Button {
                guard let onHighlight else { return }
                let error = onHighlight()
                highlightFailed = error != nil
                highlightMessage = error ?? "已保存高亮"
                onContentSizeChange?()
            } label: {
                Label("高亮所选文字", systemImage: "highlighter")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(onHighlight == nil)

            if let highlightMessage {
                Text(highlightMessage)
                    .font(.caption2)
                    .foregroundStyle(highlightFailed ? Color.red : Color.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 译文内容
            if viewModel.isLoading && viewModel.translatedText.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                    Text("翻译中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let error = viewModel.errorMessage {
                Text("错误: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(viewModel.translatedText.isEmpty ? viewModel.originalText : viewModel.translatedText)
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(width: 290)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onChange(of: viewModel.translatedText) {
            onContentSizeChange?()
        }
        .onChange(of: viewModel.isLoading) {
            onContentSizeChange?()
        }
        .onChange(of: viewModel.errorMessage) {
            onContentSizeChange?()
        }
    }
}

// MARK: - Translation Settings Sheet (Minimalist Single Engine API Key Config)

struct TranslationSettingsSheet: View {
    @Bindable var viewModel: TranslationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""

    private var engine: any TranslationEngine {
        viewModel.currentEngine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏标题
            HStack {
                Text("\(engine.displayName) 配置")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key:")
                    .font(.subheadline.weight(.medium))

                SecureField("输入 \(engine.displayName) API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Text("密钥将安全保存在本地系统的 Keychain（钥匙串）中。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let credentialFormat {
                    Text("格式：\(credentialFormat)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 底部操作按钮
            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    viewModel.saveAPIKey(apiKey, forEngineID: engine.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            apiKey = viewModel.getAPIKey(forEngineID: engine.id)
        }
    }

    private var credentialFormat: String? {
        switch engine.id {
        case "baidu":
            return "AppID#Key"
        case "youdaozhiyun":
            return "AppID#AppKey#VocabID（可选）"
        case "niutrans":
            return "API Key"
        default:
            return nil
        }
    }
}
