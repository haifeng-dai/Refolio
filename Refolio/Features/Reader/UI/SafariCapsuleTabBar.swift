import SwiftUI

struct SafariCapsuleTabBar: View {
    @Environment(LibraryViewModel.self) private var viewModel

    static let barHeight: CGFloat = 36
    static let innerPadding: CGFloat = 3
    static var tabHeight: CGFloat { barHeight - innerPadding * 2 } // 30pt

    private var totalBarWidth: CGFloat {
        let count = max(1, viewModel.openDocuments.count)
        switch count {
        case 1:
            return 380
        case 2:
            return 560
        case 3:
            return 720
        default:
            return min(920, CGFloat(count * 200))
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.openDocuments, id: \.attachmentID) { request in
                SafariCapsuleTabItem(
                    request: request,
                    isActive: viewModel.activeDocumentAttachmentID == request.attachmentID,
                    title: viewModel.title(for: request)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Self.innerPadding)
        .frame(width: totalBarWidth, height: Self.barHeight)
        .background(
            // 外部跑道大胶囊底壳：包裹整个容器，尺寸与所有标签页完全锁定
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

private struct SafariCapsuleTabItem: View {
    @Environment(LibraryViewModel.self) private var viewModel
    let request: PDFReaderRequest
    let isActive: Bool
    let title: String

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // 文档标题：清晰饱满舒展，铺满内部
            Text(title)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Safari 原生圆圈叉关闭按钮
            Button {
                viewModel.closeDocument(request)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        isCloseHovered
                            ? Color.primary
                            : (isActive ? Color.secondary : Color.secondary.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovered ? 1.0 : 0.0)
            .onHover { isCloseHovered = $0 }
            .help("Close Tab (⌘W)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        .frame(minWidth: 120, maxWidth: .infinity)
        .background(
            Group {
                if isActive {
                    // 与外部大容器完全同心等比缩小的跑道大胶囊
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.10), radius: 2, x: 0, y: 1)
                } else if isHovered {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            Group {
                if isActive {
                    // 激活态细腻边框
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
            }
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            viewModel.selectDocument(request)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Close Tab") {
                viewModel.closeDocument(request)
            }
            if viewModel.openDocuments.count > 1 {
                Button("Close Other Tabs") {
                    viewModel.openDocuments.removeAll { $0 != request }
                    viewModel.selectDocument(request)
                }
            }
            Divider()
            Button("Show in Library") {
                viewModel.showItemInLibrary(request.itemID)
            }
        }
        .help(title)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isActive)
    }
}
