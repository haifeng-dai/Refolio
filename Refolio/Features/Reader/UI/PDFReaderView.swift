import AppKit
import PDFKit
import SwiftUI

struct PDFReaderRequest: Codable, Hashable {
    let itemID: UUID
    let attachmentID: UUID
}

struct PDFReaderView: View {
    @Environment(LibraryViewModel.self) private var viewModel
    let request: PDFReaderRequest
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTool: ReaderTool = .notes
    @State private var document: PDFDocument?
    @State private var fileName = "PDF Reader"
    @State private var loadError: String?
    @State private var positionSaveError: String?
    @State private var initialPosition: PDFReadingPosition?
    @State private var currentPageIndex = 0
    @State private var isToolsPresented = true
    @State private var pdfView: ReadingPDFView?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if let pdfView {
                    PDFThumbnailPane(pdfView: pdfView)
                } else if let loadError {
                    ContentUnavailableView(
                        "Could Not Open PDF",
                        systemImage: "doc.richtext",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Pages")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            Group {
                if let document {
                    PDFKitView(
                        document: document,
                        initialPosition: initialPosition,
                        onPositionChanged: { position in
                            positionSaveError = viewModel.saveReadingPosition(
                                position,
                                for: request.attachmentID,
                                in: request.itemID
                            )
                        },
                        onCurrentPageChanged: { currentPageIndex = $0 },
                        onViewReady: { pdfView = $0 }
                    )
                } else if let loadError {
                    ContentUnavailableView(
                        "Could Not Open PDF",
                        systemImage: "doc.richtext",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(fileName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        isToolsPresented.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(isToolsPresented ? "Hide Reader Tools" : "Show Reader Tools")
                    .accessibilityLabel(isToolsPresented ? "Hide Reader Tools" : "Show Reader Tools")
                }
            }
            .inspector(isPresented: $isToolsPresented) {
                ReaderToolsView(
                    selectedTool: $selectedTool,
                    itemID: request.itemID,
                    attachmentID: request.attachmentID,
                    pageIndex: currentPageIndex
                )
                .inspectorColumnWidth(min: 300, ideal: 320, max: 480)
                .interactiveDismissDisabled()
            }
        }
        .alert(
            "Could Not Save Reading Position",
            isPresented: Binding(
                get: { positionSaveError != nil },
                set: { if !$0 { positionSaveError = nil } }
            )
        ) {
            Button("OK") { positionSaveError = nil }
        } message: {
            Text(positionSaveError ?? "Please try again.")
        }
        .task(id: request) {
            do {
                let source = try await viewModel.pdfDocument(request.attachmentID, for: request.itemID)
                guard let document = PDFDocument(url: source.url) else {
                    throw PDFReaderError.invalidPDF
                }
                fileName = source.fileName
                initialPosition = source.lastReadPosition
                currentPageIndex = source.lastReadPosition?.pageIndex ?? 0
                self.document = document
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

private enum ReaderTool: String, CaseIterable, Identifiable {
    case notes
    case annotations
    case translation
    case assistant

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .annotations: "Annot."
        case .translation: "Trans."
        case .assistant: "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .notes: "note.text"
        case .annotations: "pencil.tip.crop.circle"
        case .translation: "character.bubble"
        case .assistant: "sparkles"
        }
    }

    var placeholder: String {
        switch self {
        case .notes: ""
        case .annotations: "Page annotations will appear here."
        case .translation: "Translation tools will appear here."
        case .assistant: "AI conversations about this paper will appear here."
        }
    }
}

private struct ReaderToolsView: View {
    @Binding var selectedTool: ReaderTool
    let itemID: UUID
    let attachmentID: UUID
    let pageIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            Picker("Reader Tools", selection: $selectedTool) {
                ForEach(ReaderTool.allCases) { tool in
                    Text(tool.title)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            ScrollView {
                Group {
                    if selectedTool == .notes {
                        LiteratureNotesView(
                            itemID: itemID,
                            sourceAttachmentID: attachmentID,
                            sourcePageIndex: pageIndex
                        )
                        .padding()
                    } else {
                        ContentUnavailableView(
                            selectedTool.title,
                            systemImage: selectedTool.systemImage,
                            description: Text(selectedTool.placeholder)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct PDFThumbnailPane: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = pdfView
        view.thumbnailSize = NSSize(width: 130, height: 170)
        view.maximumNumberOfColumns = 1
        view.allowsDragging = false
        view.allowsMultipleSelection = false
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        view.pdfView = pdfView
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let initialPosition: PDFReadingPosition?
    let onPositionChanged: (PDFReadingPosition) -> Void
    let onCurrentPageChanged: (Int) -> Void
    let onViewReady: (ReadingPDFView?) -> Void

    func makeNSView(context: Context) -> ReadingPDFView {
        let view = ReadingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        context.coordinator.observe(view)
        context.coordinator.onCurrentPageChanged = onCurrentPageChanged
        DispatchQueue.main.async { [weak view, coordinator = context.coordinator] in
            guard let view else { return }
            coordinator.onViewReady(view)
        }
        restorePosition(in: view)
        return view
    }

    func updateNSView(_ view: ReadingPDFView, context: Context) {
        context.coordinator.onPositionChanged = onPositionChanged
        context.coordinator.onCurrentPageChanged = onCurrentPageChanged
        if view.document !== document {
            view.document = document
            restorePosition(in: view)
        }
    }

    static func dismantleNSView(_ view: ReadingPDFView, coordinator: Coordinator) {
        coordinator.flushPosition()
        coordinator.onViewReady(nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPositionChanged: onPositionChanged,
            onCurrentPageChanged: onCurrentPageChanged,
            onViewReady: onViewReady
        )
    }

    private func restorePosition(in view: ReadingPDFView) {
        view.afterLayout { [weak view] in
            guard let view, document.pageCount > 0 else { return }
            let savedIndex = initialPosition?.pageIndex ?? 0
            let pageIndex = min(max(savedIndex, 0), document.pageCount - 1)
            guard let page = document.page(at: pageIndex) else { return }

            if let pointX = initialPosition?.pointX, let pointY = initialPosition?.pointY {
                let destination = PDFDestination(page: page, at: CGPoint(x: pointX, y: pointY))
                if let zoom = initialPosition?.zoom, zoom > 0 {
                    view.autoScales = false
                    destination.zoom = CGFloat(zoom)
                }
                view.go(to: destination)
            } else {
                view.go(to: page)
            }
        }
    }

    final class Coordinator: NSObject {
        var onPositionChanged: (PDFReadingPosition) -> Void
        var onCurrentPageChanged: (Int) -> Void
        var onViewReady: (ReadingPDFView?) -> Void
        private weak var pdfView: PDFView?
        private var observedClipViews = Set<ObjectIdentifier>()
        private var pendingSave: DispatchWorkItem?

        init(
            onPositionChanged: @escaping (PDFReadingPosition) -> Void,
            onCurrentPageChanged: @escaping (Int) -> Void,
            onViewReady: @escaping (ReadingPDFView?) -> Void
        ) {
            self.onPositionChanged = onPositionChanged
            self.onCurrentPageChanged = onCurrentPageChanged
            self.onViewReady = onViewReady
        }

        func observe(_ view: PDFView) {
            pdfView = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(readingPositionChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(readingPositionChanged(_:)),
                name: .PDFViewScaleChanged,
                object: view
            )
            observeClipViews(in: view)
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.observeClipViews(in: view)
            }
        }

        func flushPosition() {
            pendingSave?.cancel()
            pendingSave = nil
            savePosition()
        }

        @objc private func readingPositionChanged(_ notification: Notification) {
            scheduleSave()
        }

        @objc private func scrollBoundsChanged(_ notification: Notification) {
            scheduleSave()
        }

        private func observeClipViews(in view: NSView) {
            if let clipView = view as? NSClipView,
               observedClipViews.insert(ObjectIdentifier(clipView)).inserted {
                clipView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(scrollBoundsChanged(_:)),
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
            view.subviews.forEach(observeClipViews(in:))
        }

        private func scheduleSave() {
            reportCurrentPage()
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSave = nil
                self.savePosition()
            }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        private func savePosition() {
            guard let view = pdfView,
                  let destination = view.currentDestination,
                  let page = destination.page,
                  let document = view.document else { return }
            let pageIndex = document.index(for: page)
            let point = destination.point
            guard pageIndex != NSNotFound, point.x.isFinite, point.y.isFinite else { return }
            onPositionChanged(
                PDFReadingPosition(
                    pageIndex: pageIndex,
                    pointX: Double(point.x),
                    pointY: Double(point.y),
                    zoom: Double(view.scaleFactor)
                )
            )
        }

        private func reportCurrentPage() {
            guard let view = pdfView,
                  let destination = view.currentDestination,
                  let page = destination.page,
                  let document = view.document else { return }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return }
            onCurrentPageChanged(pageIndex)
        }

        deinit {
            pendingSave?.cancel()
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private final class ReadingPDFView: PDFView {
    private var afterLayoutAction: (() -> Void)?

    func afterLayout(_ action: @escaping () -> Void) {
        afterLayoutAction = action
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard window != nil,
              bounds.width > 0,
              bounds.height > 0,
              let action = afterLayoutAction else { return }
        afterLayoutAction = nil
        DispatchQueue.main.async(execute: action)
    }
}

private enum PDFReaderError: LocalizedError {
    case invalidPDF

    var errorDescription: String? { "The file is missing or is not a readable PDF." }
}
