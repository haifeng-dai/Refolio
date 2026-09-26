import AppKit
import SwiftUI

// MARK: - Translation Workstation (Right Sidebar Detail Panel)

struct TranslationWorkstationView: View {
    @Bindable var viewModel: TranslationViewModel
    let onOpenDetailColumn: (() -> Void)?

    init(viewModel: TranslationViewModel, onOpenDetailColumn: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenDetailColumn = onOpenDetailColumn
    }

    var body: some View {
        VStack(spacing: 14) {
            headerBar

            if viewModel.originalText.isEmpty && viewModel.history.isEmpty {
                emptyPlaceholder
            } else {
                contentSections
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
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
                .padding(.horizontal, 8)
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
                Button("清空历史记录", role: .destructive) {
                    viewModel.clearHistory()
                }
                .disabled(viewModel.history.isEmpty)
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
            if !viewModel.originalText.isEmpty {
                originalCard
                translatedCard
            }

            if !viewModel.history.isEmpty {
                historySection
            }
        }
    }

    // MARK: - Original Text Card

    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("原文")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.originalText.count) 字符")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

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
            }

            Text(viewModel.originalText)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    Button("重试") {
                        viewModel.retranslate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("划词历史")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.history.count) 条")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            VStack(spacing: 6) {
                ForEach(viewModel.history) { item in
                    Button {
                        viewModel.originalText = item.original
                        viewModel.translatedText = item.translated
                        viewModel.targetLanguage = item.targetLanguage
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.original)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)

                            Text(item.translated)
                                .font(.caption2)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Floating Popover (Overlay directly near selection)

struct TranslationFloatingPopover: View {
    @Bindable var viewModel: TranslationViewModel
    let onOpenDetailPanel: () -> Void
    var onClose: (() -> Void)? = nil

    @State private var isCopied: Bool = false

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

            // 原文简览
            Text(viewModel.originalText)
                .font(.system(size: 11.5, weight: .regular, design: .serif))
                .lineLimit(2)
                .foregroundStyle(.secondary)

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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}
