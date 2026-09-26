import AppKit
import PDFKit
import SwiftUI

struct PDFReaderRequest: Codable, Hashable {
    let itemID: UUID
    let attachmentID: UUID
}

extension Notification.Name {
    static let togglePDFReaderDetailColumn = Notification.Name("RefolioTogglePDFReaderDetailColumn")
}

@Observable
final class PDFReaderSplitViewState {
    var isDetailCollapsed: Bool = false
}

private enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails
    case outline
    case annotations

    var id: Self { self }

    var title: String {
        switch self {
        case .thumbnails: "Pages"
        case .outline: "Outline"
        case .annotations: "Annot."
        }
    }

    var fullTitle: String {
        switch self {
        case .thumbnails: "Page Thumbnails"
        case .outline: "Table of Contents"
        case .annotations: "Annotations"
        }
    }

    var systemImage: String {
        switch self {
        case .thumbnails: "rectangle.grid.1x2"
        case .outline: "list.bullet.indent"
        case .annotations: "pencil.tip"
        }
    }
}

private struct PDFOutlineNode: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let destination: PDFDestination?
    let action: PDFAction?
    let pageIndex: Int?
    let children: [PDFOutlineNode]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PDFOutlineNode, rhs: PDFOutlineNode) -> Bool {
        lhs.id == rhs.id
    }
}

private struct PDFAnnotationItem: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let typeName: String
    let contents: String
    let color: NSColor?
    let page: PDFPage
}

private func buildOutlineNodes(from outline: PDFOutline, in document: PDFDocument) -> [PDFOutlineNode] {
    var nodes: [PDFOutlineNode] = []
    for i in 0..<outline.numberOfChildren {
        guard let child = outline.child(at: i) else { continue }
        let title = child.label ?? "Untitled"
        let destination = child.destination
        let action = child.action

        var pageIndex: Int? = nil
        if let page = destination?.page {
            let idx = document.index(for: page)
            if idx != NSNotFound { pageIndex = idx }
        } else if let goto = action as? PDFActionGoTo, let page = goto.destination.page {
            let idx = document.index(for: page)
            if idx != NSNotFound { pageIndex = idx }
        }

        let subChildren = child.numberOfChildren > 0 ? buildOutlineNodes(from: child, in: document) : nil
        nodes.append(
            PDFOutlineNode(
                title: title,
                destination: destination,
                action: action,
                pageIndex: pageIndex,
                children: subChildren
            )
        )
    }
    return nodes
}

private func extractAnnotations(from document: PDFDocument) -> [PDFAnnotationItem] {
    var items: [PDFAnnotationItem] = []
    for i in 0..<document.pageCount {
        guard let page = document.page(at: i) else { continue }
        for ann in page.annotations {
            let subtype = ann.type ?? ""
            if subtype == "Link" || subtype == "Widget" { continue }
            let text = ann.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let typeLabel = readableAnnotationType(subtype)
            let displayText = text.isEmpty ? typeLabel : text
            items.append(
                PDFAnnotationItem(
                    pageIndex: i,
                    typeName: typeLabel,
                    contents: displayText,
                    color: ann.color,
                    page: page
                )
            )
        }
    }
    return items
}

private func readableAnnotationType(_ type: String) -> String {
    switch type {
    case "Highlight": return "Highlight"
    case "Underline": return "Underline"
    case "StrikeOut": return "Strikeout"
    case "Text": return "Note"
    case "FreeText": return "Text Box"
    default: return type.isEmpty ? "Annotation" : type
    }
}

struct PDFReaderView: View {
    private let sidebarMinimumWidth: CGFloat = 260
    private let sidebarIdealWidth: CGFloat = 280
    private let sidebarMaximumWidth: CGFloat = 400

    private let contentMinimumWidth: CGFloat = 280
    private let contentIdealWidth: CGFloat = 600

    private let detailMinimumWidth: CGFloat = 200
    private let detailIdealWidth: CGFloat = 300
    private let detailMaximumWidth: CGFloat = 750

    @Environment(LibraryViewModel.self) private var viewModel
    let request: PDFReaderRequest

    @State private var splitViewState = PDFReaderSplitViewState()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedSidebarTab: SidebarTab = .thumbnails
    @State private var selectedTool: ReaderTool = .notes
    @State private var translationViewModel = TranslationViewModel()
    @State private var document: PDFDocument?
    @State private var fileName = "PDF Reader"
    @State private var loadError: String?
    @State private var positionSaveError: String?
    @State private var initialPosition: PDFReadingPosition?
    @State private var currentPageIndex = 0
    @State private var pdfView: ReadingPDFView?
    @State private var outlineNodes: [PDFOutlineNode] = []
    @State private var annotations: [PDFAnnotationItem] = []

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle(selectedSidebarTab.fullTitle)
                .navigationSplitViewColumnWidth(
                    min: sidebarMinimumWidth,
                    ideal: sidebarIdealWidth,
                    max: sidebarMaximumWidth
                )
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Library", systemImage: "books.vertical") {
                            viewModel.workspaceMode = .library
                        }
                        .labelStyle(.iconOnly)
                        .help("Back to Library")
                    }
                }
        } content: {
            pdfContent
                .navigationTitle(fileName)
                .navigationSubtitle(document.map { "Page \(currentPageIndex + 1) of \($0.pageCount)" } ?? "")
                .navigationSplitViewColumnWidth(min: contentMinimumWidth, ideal: contentIdealWidth)
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button {
                            pdfView?.goToPreviousPage(nil)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .labelStyle(.iconOnly)
                        .help("Previous Page")
                        .disabled(currentPageIndex <= 0)

                        Button {
                            pdfView?.goToNextPage(nil)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .labelStyle(.iconOnly)
                        .help("Next Page")
                        .disabled(document == nil || currentPageIndex >= (document?.pageCount ?? 1) - 1)

                        Divider()

                        Button {
                            pdfView?.zoomOut(nil)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .labelStyle(.iconOnly)
                        .help("Zoom Out")

                        Button {
                            pdfView?.zoomIn(nil)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .labelStyle(.iconOnly)
                        .help("Zoom In")

                        Button {
                            pdfView?.autoScales = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .labelStyle(.iconOnly)
                        .help("Fit to Page")
                    }

                    ToolbarItem(placement: .automatic) {
                        Button {
                            NotificationCenter.default.post(name: .togglePDFReaderDetailColumn, object: nil)
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                        .help(splitViewState.isDetailCollapsed ? "Show Tools (⌘⌥0)" : "Hide Tools (⌘⌥0)")
                        .keyboardShortcut("0", modifiers: [.command, .option])
                    }
                }
        } detail: {
            detailPanel
                .navigationSplitViewColumnWidth(
                    min: detailMinimumWidth,
                    ideal: detailIdealWidth,
                    max: detailMaximumWidth
                )
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(PDFReaderSplitViewPriorityConfigurator(splitViewState: splitViewState))
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

                if let root = document.outlineRoot {
                    outlineNodes = buildOutlineNodes(from: root, in: document)
                } else {
                    outlineNodes = []
                }
                annotations = extractAnnotations(from: document)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            RefolioSegmentedControl(
                items: SidebarTab.allCases,
                selection: $selectedSidebarTab,
                title: { $0.title },
                icon: { $0.systemImage },
                helpText: { $0.fullTitle }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch selectedSidebarTab {
                case .thumbnails:
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

                case .outline:
                    if outlineNodes.isEmpty {
                        ContentUnavailableView(
                            "No Outline",
                            systemImage: "list.bullet.indent",
                            description: Text("This document does not contain a table of contents.")
                        )
                    } else {
                        List {
                            OutlineGroup(outlineNodes, children: \.children) { node in
                                Button {
                                    jumpToOutline(node)
                                } label: {
                                    HStack {
                                        Text(node.title)
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if let pageIndex = node.pageIndex {
                                            Text(String(pageIndex + 1))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listStyle(.sidebar)
                    }

                case .annotations:
                    annotationsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var annotationsView: some View {
        if annotations.isEmpty {
            ContentUnavailableView(
                "No Annotations",
                systemImage: "pencil.tip",
                description: Text("Document annotations and highlights will appear here.")
            )
        } else {
            List(annotations) { item in
                Button {
                    pdfView?.go(to: item.page)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.typeName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text("Page \(item.pageIndex + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(item.contents)
                            .font(.body)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
        }
    }

    private func jumpToOutline(_ node: PDFOutlineNode) {
        guard let pdfView else { return }
        if let dest = node.destination {
            pdfView.go(to: dest)
        } else if let goto = node.action as? PDFActionGoTo {
            pdfView.go(to: goto.destination)
        } else if let pageIdx = node.pageIndex, let page = document?.page(at: pageIdx) {
            pdfView.go(to: page)
        }
    }

    private func openTranslationDetailPanel() {
        selectedTool = .translation
        if splitViewState.isDetailCollapsed {
            NotificationCenter.default.post(name: .togglePDFReaderDetailColumn, object: nil)
        }
    }

    @ViewBuilder
    private var pdfContent: some View {
        Group {
            if let document {
                PDFKitView(
                    document: document,
                    initialPosition: initialPosition,
                    translationViewModel: translationViewModel,
                    onOpenDetailPanel: openTranslationDetailPanel,
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
    }

    @ViewBuilder
    private var detailPanel: some View {
        ReaderToolsView(
            selectedTool: $selectedTool,
            itemID: request.itemID,
            attachmentID: request.attachmentID,
            pageIndex: currentPageIndex,
            translationViewModel: translationViewModel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private enum ReaderTool: String, CaseIterable, Identifiable {
    case notes
    case translation
    case assistant

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .translation: "Trans."
        case .assistant: "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .notes: "note.text"
        case .translation: "character.bubble"
        case .assistant: "sparkles"
        }
    }

    var placeholder: String {
        switch self {
        case .notes: ""
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
    @Bindable var translationViewModel: TranslationViewModel

    var body: some View {
        VStack(spacing: 0) {
            RefolioSegmentedControl(
                items: ReaderTool.allCases,
                selection: $selectedTool,
                title: { $0.title },
                icon: { $0.systemImage },
                helpText: { $0.title }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

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
                    } else if selectedTool == .translation {
                        TranslationWorkstationView(viewModel: translationViewModel)
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
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct PDFThumbnailPane: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> AutoSizingPDFThumbnailView {
        let view = AutoSizingPDFThumbnailView()
        view.pdfView = pdfView
        view.maximumNumberOfColumns = 1
        view.allowsDragging = false
        view.allowsMultipleSelection = false
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: AutoSizingPDFThumbnailView, context: Context) {
        view.pdfView = pdfView
    }
}

private final class AutoSizingPDFThumbnailView: PDFThumbnailView {
    override func layout() {
        super.layout()
        updateThumbnailSize()
    }

    private func updateThumbnailSize() {
        let availableWidth = bounds.width
        guard availableWidth > 40 else { return }

        let targetWidth = max(70, availableWidth - 32)
        let aspectRatio: CGFloat
        if let firstPage = pdfView?.document?.page(at: 0) {
            let pageBounds = firstPage.bounds(for: .cropBox)
            aspectRatio = pageBounds.width > 0 ? (pageBounds.height / pageBounds.width) : 1.414
        } else {
            aspectRatio = 1.414
        }

        let targetHeight = targetWidth * aspectRatio
        let newSize = NSSize(width: targetWidth, height: targetHeight)

        if abs(thumbnailSize.width - newSize.width) > 2 {
            thumbnailSize = newSize
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let initialPosition: PDFReadingPosition?
    let translationViewModel: TranslationViewModel
    let onOpenDetailPanel: () -> Void
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
        context.coordinator.translationViewModel = translationViewModel
        context.coordinator.onOpenDetailPanel = onOpenDetailPanel
        DispatchQueue.main.async { [weak view, coordinator = context.coordinator] in
            guard let view else { return }
            coordinator.onViewReady(view)
        }
        restorePosition(in: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: ReadingPDFView, context: Context) {
        context.coordinator.onPositionChanged = onPositionChanged
        context.coordinator.onCurrentPageChanged = onCurrentPageChanged
        context.coordinator.translationViewModel = translationViewModel
        context.coordinator.onOpenDetailPanel = onOpenDetailPanel
        if view.document !== document {
            view.document = document
            restorePosition(in: view, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ view: ReadingPDFView, coordinator: Coordinator) {
        coordinator.flushPosition()
        coordinator.closePopover()
        coordinator.onViewReady(nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            translationViewModel: translationViewModel,
            onOpenDetailPanel: onOpenDetailPanel,
            onPositionChanged: onPositionChanged,
            onCurrentPageChanged: onCurrentPageChanged,
            onViewReady: onViewReady
        )
    }

    private func restorePosition(in view: ReadingPDFView, coordinator: Coordinator) {
        coordinator.isReadyToSave = false
        view.autoScales = true

        guard let initialPosition, initialPosition.pageIndex > 0 || (initialPosition.pointY != nil) else {
            coordinator.isReadyToSave = true
            return
        }

        view.afterLayout { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            self.attemptRestore(to: initialPosition, in: view, coordinator: coordinator)
        }
    }

    private func attemptRestore(to position: PDFReadingPosition, in view: ReadingPDFView, coordinator: Coordinator) {
        let pageIndex = position.pageIndex
        guard let document = view.document, pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            coordinator.isReadyToSave = true
            return
        }

        view.autoScales = true
        let performGo = {
            if let pointY = position.pointY, pointY.isFinite {
                let destination = PDFDestination(page: page, at: CGPoint(x: kPDFDestinationUnspecifiedValue, y: CGFloat(pointY)))
                view.go(to: destination)
            } else {
                view.go(to: page)
            }
        }

        performGo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak view] in
            guard let view else { return }
            performGo()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak coordinator] in
            coordinator?.isReadyToSave = true
        }
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var isReadyToSave: Bool = false
        var translationViewModel: TranslationViewModel
        var onOpenDetailPanel: () -> Void
        var onPositionChanged: (PDFReadingPosition) -> Void
        var onCurrentPageChanged: (Int) -> Void
        var onViewReady: (ReadingPDFView?) -> Void
        private weak var pdfView: PDFView?
        private var observedClipViews = Set<ObjectIdentifier>()
        private var pendingSave: DispatchWorkItem?
        private var popover: NSPopover?

        init(
            translationViewModel: TranslationViewModel,
            onOpenDetailPanel: @escaping () -> Void,
            onPositionChanged: @escaping (PDFReadingPosition) -> Void,
            onCurrentPageChanged: @escaping (Int) -> Void,
            onViewReady: @escaping (ReadingPDFView?) -> Void
        ) {
            self.translationViewModel = translationViewModel
            self.onOpenDetailPanel = onOpenDetailPanel
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged(_:)),
                name: .PDFViewSelectionChanged,
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
            guard isReadyToSave else { return }
            savePosition()
        }

        func closePopover() {
            popover?.close()
            popover = nil
        }

        @objc private func selectionChanged(_ notification: Notification) {
            guard let view = pdfView else { return }
            guard let selection = view.currentSelection,
                  let rawText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawText.count > 1,
                  let page = selection.pages.first else {
                popover?.close()
                return
            }

            let bounds = selection.bounds(for: page)
            let viewRect = view.convert(bounds, from: page)
            guard viewRect.width > 0, viewRect.height > 0 else { return }

            translationViewModel.handleSelectionChange(rawText: rawText, anchorRect: viewRect)

            if translationViewModel.isFloatingPopoverEnabled {
                showPopover(for: viewRect, in: view)
            }
        }

        private func showPopover(for rect: NSRect, in view: PDFView) {
            if popover == nil {
                let p = NSPopover()
                p.behavior = .transient
                p.animates = true
                p.delegate = self
                let content = TranslationFloatingPopover(
                    viewModel: translationViewModel,
                    onOpenDetailPanel: { [weak self, weak p] in
                        p?.close()
                        self?.onOpenDetailPanel()
                    },
                    onClose: { [weak p] in
                        p?.close()
                    },
                    onContentSizeChange: { [weak self] in
                        self?.updatePopoverSize()
                    }
                )
                p.contentViewController = NSHostingController(rootView: content)
                self.popover = p
            }

            guard let popover = self.popover else { return }
            if popover.isShown {
                popover.positioningRect = rect
            } else {
                popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            }
            updatePopoverSize()
        }

        private func updatePopoverSize() {
            guard let popover = self.popover, popover.isShown,
                  let contentVC = popover.contentViewController else { return }
            DispatchQueue.main.async {
                contentVC.view.layoutSubtreeIfNeeded()
                let targetSize = contentVC.view.fittingSize
                guard targetSize.width > 0, targetSize.height > 0 else { return }
                popover.contentSize = targetSize
                let currentRect = popover.positioningRect
                popover.positioningRect = currentRect
            }
        }

        func popoverDidClose(_ notification: Notification) {
            translationViewModel.isShowingFloatingPopover = false
        }

        @objc private func readingPositionChanged(_ notification: Notification) {
            scheduleSave()
        }

        @objc private func scrollBoundsChanged(_ notification: Notification) {
            scheduleSave()
            if let popover = self.popover, popover.isShown,
               let view = pdfView,
               let selection = view.currentSelection,
               let page = selection.pages.first {
                let bounds = selection.bounds(for: page)
                let viewRect = view.convert(bounds, from: page)
                if view.bounds.intersects(viewRect) {
                    popover.positioningRect = viewRect
                } else {
                    popover.close()
                }
            }
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

        private func currentReadingPosition() -> (pageIndex: Int, pointY: Double)? {
            guard let view = pdfView,
                  let document = view.document,
                  document.pageCount > 0 else { return nil }

            let topInView = NSPoint(x: view.bounds.midX, y: view.bounds.maxY)
            guard let page = view.page(for: topInView, nearest: true) ?? view.currentPage else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }

            let topOnPage = view.convert(topInView, to: page)
            let pageBounds = page.bounds(for: view.displayBox)
            let safeY = min(max(topOnPage.y, pageBounds.minY), pageBounds.maxY)
            return (pageIndex, Double(safeY))
        }

        private func savePosition() {
            guard isReadyToSave else { return }
            guard let (pageIndex, pointY) = currentReadingPosition() else { return }
            onPositionChanged(
                PDFReadingPosition(
                    pageIndex: pageIndex,
                    pointX: 0.0,
                    pointY: pointY,
                    zoom: nil
                )
            )
        }

        private func reportCurrentPage() {
            guard let (pageIndex, _) = currentReadingPosition() else { return }
            onCurrentPageChanged(pageIndex)
        }

        deinit {
            pendingSave?.cancel()
            popover?.close()
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private final class ReadingPDFView: PDFView {
    private var afterLayoutAction: (() -> Void)?

    func afterLayout(_ action: @escaping () -> Void) {
        afterLayoutAction = action
        needsLayout = true
        triggerAfterLayoutIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        triggerAfterLayoutIfNeeded()
    }

    override func layout() {
        super.layout()
        triggerAfterLayoutIfNeeded()
    }

    private func triggerAfterLayoutIfNeeded() {
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

private final class PDFReaderSplitConfigObserverView: NSView {
    var splitViewState: PDFReaderSplitViewState?
    private var detailObservation: NSKeyValueObservation?
    private weak var splitVC: NSSplitViewController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard self.window != nil else {
            NotificationCenter.default.removeObserver(self, name: .togglePDFReaderDetailColumn, object: nil)
            return
        }

        NotificationCenter.default.removeObserver(self, name: .togglePDFReaderDetailColumn, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleDetailNotification),
            name: .togglePDFReaderDetailColumn,
            object: nil
        )
        applyConfiguration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyConfiguration()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.applyConfiguration()
        }
    }

    @objc private func handleToggleDetailNotification() {
        guard let window = self.window, window.isKeyWindow else { return }
        guard let svc = splitVC ?? (findSplitView(in: window.contentView ?? self)?.delegate as? NSSplitViewController),
              svc.splitViewItems.count >= 3 else { return }
        let detailItem = svc.splitViewItems[2]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            detailItem.animator().isCollapsed.toggle()
        }
    }

    private func findSplitView(in current: NSView) -> NSSplitView? {
        if let sv = current as? NSSplitView { return sv }
        for sub in current.subviews {
            if let sv = findSplitView(in: sub) { return sv }
        }
        return nil
    }

    func applyConfiguration() {
        guard let window = self.window else { return }
        guard let splitView = findSplitView(in: window.contentView ?? self),
              let splitVC = splitView.delegate as? NSSplitViewController,
              splitVC.splitViewItems.count >= 3 else {
            return
        }

        self.splitVC = splitVC
        let items = splitVC.splitViewItems

        // 0: Sidebar (最坚固：防止宽屏或拖拽时变形)
        items[0].holdingPriority = NSLayoutConstraint.Priority(280)
        items[0].minimumThickness = 260
        items[0].maximumThickness = 400

        // 1: Middle Content (主舞台：吸收所有多余窗口宽度)
        items[1].holdingPriority = NSLayoutConstraint.Priority(100)
        items[1].minimumThickness = 280
        items[1].maximumThickness = NSSplitViewItem.unspecifiedDimension

        // 2: Detail (右侧栏：自由调节，绝不加 Auto Layout 硬死锁，不波及左侧栏)
        items[2].holdingPriority = NSLayoutConstraint.Priority(200)
        items[2].minimumThickness = 200
        items[2].maximumThickness = 750
        items[2].canCollapse = true

        if detailObservation == nil {
            detailObservation = items[2].observe(\.isCollapsed, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.splitViewState?.isDetailCollapsed = item.isCollapsed
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        detailObservation?.invalidate()
    }
}

private struct PDFReaderSplitViewPriorityConfigurator: NSViewRepresentable {
    let splitViewState: PDFReaderSplitViewState

    func makeNSView(context: Context) -> PDFReaderSplitConfigObserverView {
        let view = PDFReaderSplitConfigObserverView()
        view.splitViewState = splitViewState
        return view
    }

    func updateNSView(_ nsView: PDFReaderSplitConfigObserverView, context: Context) {
        nsView.splitViewState = splitViewState
        nsView.applyConfiguration()
    }
}
