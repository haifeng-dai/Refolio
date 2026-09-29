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
    var sidebarWidth: CGFloat = 280
    var detailWidth: CGFloat = 0
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

private enum PDFAnnotationItemID: Hashable {
    case documentAnnotation(ObjectIdentifier)
    case textHighlight(UUID)
    case rectangleMark(UUID)
}

private struct PDFAnnotationItem: Identifiable {
    let id: PDFAnnotationItemID
    let pageIndex: Int
    let typeName: String
    let contents: String?
    let color: NSColor?
    let page: PDFPage
    let bounds: CGRect
    let annotation: PDFAnnotation?
    let comments: [AnnotationComment]
}

private final class PDFAnnotationMenuTarget: NSObject {
    var actions: [String: () -> Void] = [:]

    @objc func perform(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        actions[key]?()
    }
}

private final class PDFAnnotationColorPaletteView: NSView {
    private let colors = ZoteroAnnotationColor.allCases
    private let onSelect: (ZoteroAnnotationColor) -> Void
    private let dotSize: CGFloat = 15
    private let spacing: CGFloat = 8
    private let horizontalPadding: CGFloat = 10

    init(onSelect: @escaping (ZoteroAnnotationColor) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        frame.size = intrinsicContentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: horizontalPadding * 2 + dotSize * CGFloat(colors.count) + spacing * CGFloat(max(colors.count - 1, 0)),
            height: 34
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let startX = horizontalPadding
        let centerY = bounds.midY
        for (index, color) in colors.enumerated() {
            let x = startX + CGFloat(index) * (dotSize + spacing)
            let rect = NSRect(x: x, y: centerY - dotSize / 2, width: dotSize, height: dotSize)
            NSColor(
                srgbRed: CGFloat(color.borderColor.red),
                green: CGFloat(color.borderColor.green),
                blue: CGFloat(color.borderColor.blue),
                alpha: CGFloat(color.borderColor.alpha)
            ).setFill()
            NSBezierPath(ovalIn: rect).fill()

            NSColor.controlTextColor.withAlphaComponent(0.2).setStroke()
            let border = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
            border.lineWidth = 0.5
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = colors.indices.first(where: { dotRect(for: $0).contains(point) }) else { return }
        onSelect(colors[index])
        enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()
    }

    private func dotRect(for index: Int) -> NSRect {
        NSRect(
            x: horizontalPadding + CGFloat(index) * (dotSize + spacing),
            y: bounds.midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        ).insetBy(dx: -4, dy: -4)
    }
}

private final class PDFAnnotationContextMenu: NSMenu {
    private let actionTarget: PDFAnnotationMenuTarget

    init(actionTarget: PDFAnnotationMenuTarget) {
        self.actionTarget = actionTarget
        super.init(title: "Annotation")
        allowsContextMenuPlugIns = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
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

private func extractAnnotations(
    from document: PDFDocument,
    including highlights: [TextHighlight] = [],
    rectangleMarks: [RectangleMark] = [],
    comments: [AnnotationComment] = []
) -> [PDFAnnotationItem] {
    var items: [PDFAnnotationItem] = []
    for i in 0..<document.pageCount {
        guard let page = document.page(at: i) else { continue }
        for ann in page.annotations {
            let subtype = ann.type ?? ""
            if ann.userName?.hasPrefix(PDFTextHighlightRenderer.annotationUserNamePrefix) == true { continue }
            if ann.userName?.hasPrefix(PDFRectangleMarkRenderer.annotationUserNamePrefix) == true { continue }
            if subtype == "Link" || subtype == "Widget" { continue }
            let text = ann.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let typeLabel = readableAnnotationType(subtype)
            let displayText = text.isEmpty ? typeLabel : text
            items.append(
                PDFAnnotationItem(
                    id: .documentAnnotation(ObjectIdentifier(ann)),
                    pageIndex: i,
                    typeName: typeLabel,
                    contents: displayText,
                    color: ann.color,
                    page: page,
                    bounds: ann.bounds.standardized,
                    annotation: ann,
                    comments: []
                )
            )
        }
    }

    for highlight in highlights {
        guard let pageGeometry = highlight.pages.min(by: { $0.pageIndex < $1.pageIndex }),
              let page = document.page(at: pageGeometry.pageIndex) else {
            continue
        }
        let rectangles = pageGeometry.rectangles.compactMap { geometry -> CGRect? in
            let rect = CGRect(
                x: CGFloat(geometry.x),
                y: CGFloat(geometry.y),
                width: CGFloat(geometry.width),
                height: CGFloat(geometry.height)
            ).standardized
            guard rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite,
                  rect.width > 0,
                  rect.height > 0 else {
                return nil
            }
            return rect
        }
        guard let firstRect = rectangles.first else { continue }
        let bounds = rectangles.dropFirst().reduce(firstRect) { $0.union($1) }
        items.append(
            PDFAnnotationItem(
                id: .textHighlight(highlight.id),
                pageIndex: pageGeometry.pageIndex,
                typeName: "Highlight",
                contents: highlight.selectedText,
                color: NSColor(
                    srgbRed: CGFloat(highlight.color.red),
                    green: CGFloat(highlight.color.green),
                    blue: CGFloat(highlight.color.blue),
                    alpha: CGFloat(highlight.color.alpha)
                ),
                page: page,
                bounds: bounds,
                annotation: nil,
                comments: comments.filter { $0.annotationID == highlight.id }
            )
        )
    }

    for mark in rectangleMarks {
        guard let page = document.page(at: mark.pageIndex) else { continue }
        let bounds = CGRect(
            x: mark.x,
            y: mark.y,
            width: mark.width,
            height: mark.height
        ).standardized
        guard bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else {
            continue
        }
        items.append(
            PDFAnnotationItem(
                id: .rectangleMark(mark.id),
                pageIndex: mark.pageIndex,
                typeName: "Rectangle",
                contents: nil,
                color: NSColor(
                    srgbRed: CGFloat(mark.color.red),
                    green: CGFloat(mark.color.green),
                    blue: CGFloat(mark.color.blue),
                    alpha: CGFloat(mark.color.alpha)
                ),
                page: page,
                bounds: bounds,
                annotation: nil,
                comments: comments.filter { $0.annotationID == mark.id }
            )
        )
    }

    return items.sorted {
        if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
        if $0.bounds.maxY != $1.bounds.maxY { return $0.bounds.maxY > $1.bounds.maxY }
        return $0.bounds.minX < $1.bounds.minX
    }
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
    @State private var annotationError: String?
    @State private var initialPosition: PDFReadingPosition?
    @State private var currentPageIndex = 0
    @State private var isRectangleToolActive = false
    @State private var pdfView: ReadingPDFView?
    @State private var outlineNodes: [PDFOutlineNode] = []
    @State private var annotations: [PDFAnnotationItem] = []
    @State private var textHighlights: [TextHighlight] = []
    @State private var rectangleMarks: [RectangleMark] = []
    @State private var annotationComments: [AnnotationComment] = []
    @State private var editingAnnotation: PDFAnnotationItem?
    @State private var editingComment: AnnotationComment?
    @State private var annotationCommentDraft = ""
    @State private var isAnnotationCommentEditorPresented = false
    @State private var selectedAnnotationID: PDFAnnotationItemID?

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
                .navigationTitle("")
                .navigationSplitViewColumnWidth(min: contentMinimumWidth, ideal: contentIdealWidth)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        SafariCapsuleTabBar()
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            pdfView?.goToPreviousPage(nil)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .labelStyle(.iconOnly)
                        .help("Previous Page")
                        .disabled(currentPageIndex <= 0)

                        if let document {
                            Text("\(currentPageIndex + 1) / \(document.pageCount)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

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

                        Button("Box", systemImage: "rectangle.dashed") {
                            isRectangleToolActive.toggle()
                            if isRectangleToolActive {
                                pdfView?.clearSelection()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(isRectangleToolActive ? .accentColor : .secondary)
                        .help(isRectangleToolActive ? "Stop Adding Rectangle Annotations" : "Add Rectangle Annotation")
                        .disabled(document == nil)

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
                currentPageIndex = 0
                annotationError = nil
                textHighlights = []
                rectangleMarks = []
                annotationComments = []
                isRectangleToolActive = false
                self.document = document

                if let root = document.outlineRoot {
                    outlineNodes = buildOutlineNodes(from: root, in: document)
                } else {
                    outlineNodes = []
                }
                do {
                    let highlights = try viewModel.textHighlights(
                        for: request.attachmentID,
                        in: request.itemID
                    )
                    for highlight in highlights {
                        let renderableHighlight: TextHighlight
                        if let repairedPages = PDFTextHighlightGeometryBuilder.recoveredPages(
                            for: highlight,
                            in: document
                        ), repairedPages != highlight.pages {
                            renderableHighlight = TextHighlight(
                                id: highlight.id,
                                selectedText: highlight.selectedText,
                                createdAt: highlight.createdAt,
                                color: highlight.color,
                                pages: repairedPages
                            )
                            do {
                                _ = try viewModel.updateTextHighlightGeometry(
                                    repairedPages,
                                    for: highlight.id,
                                    attachmentID: request.attachmentID,
                                    in: request.itemID
                                )
                            } catch {
                                annotationError = error.localizedDescription
                            }
                        } else {
                            renderableHighlight = highlight
                        }
                        textHighlights.append(renderableHighlight)
                        do {
                            try PDFTextHighlightRenderer.apply(renderableHighlight, to: document)
                        } catch {
                            annotationError = error.localizedDescription
                        }
                    }
                } catch {
                    annotationError = error.localizedDescription
                }

                do {
                    let marks = try viewModel.rectangleMarks(
                        for: request.attachmentID,
                        in: request.itemID
                    )
                    rectangleMarks = marks
                    for mark in marks {
                        do {
                            try PDFRectangleMarkRenderer.apply(mark, to: document)
                        } catch {
                            annotationError = error.localizedDescription
                        }
                    }
                } catch {
                    annotationError = error.localizedDescription
                }
                do {
                    annotationComments = try viewModel.annotationComments(
                        for: request.attachmentID,
                        in: request.itemID
                    )
                } catch {
                    annotationError = error.localizedDescription
                }
                annotations = extractAnnotations(
                    from: document,
                    including: textHighlights,
                    rectangleMarks: rectangleMarks,
                    comments: annotationComments
                )
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
                        PDFThumbnailPane(pdfView: pdfView, currentPageIndex: currentPageIndex)
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
        Group {
            if annotations.isEmpty {
                ContentUnavailableView(
                    "No Annotations",
                    systemImage: "pencil.tip",
                    description: Text("Document annotations and highlights will appear here.")
                )
            } else {
                List(annotations) { item in
                    Button {
                        selectedAnnotationID = item.id
                        jumpToAnnotation(item)
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
                            if let contents = item.contents {
                                Text(contents)
                                    .font(.body)
                                    .lineLimit(3)
                                    .foregroundStyle(.primary)
                            }
                            ForEach(item.comments) { comment in
                                Label {
                                    Text(comment.content)
                                        .font(.caption)
                                        .lineLimit(2)
                                } icon: {
                                    Image(systemName: "text.bubble")
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedAnnotationID == item.id
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                    )
                    .contextMenu { annotationContextMenu(for: item) }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(isPresented: $isAnnotationCommentEditorPresented) {
            annotationCommentEditor
        }
    }

    private var annotationCommentEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editingComment == nil ? "Add Comment" : "Edit Comment")
                .font(.title2.weight(.semibold))

            if let editingAnnotation {
                Text(editingAnnotation.contents ?? editingAnnotation.typeName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            TextEditor(text: $annotationCommentDraft)
                .font(.body)
                .frame(minHeight: 140)

            HStack {
                Spacer()
                Button("Cancel") {
                    isAnnotationCommentEditorPresented = false
                }
                Button("Save") {
                    saveAnnotationComment()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
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

    private func jumpToAnnotation(_ item: PDFAnnotationItem) {
        selectedAnnotationID = item.id
        guard let pdfView else { return }
        guard item.bounds.width.isFinite,
              item.bounds.height.isFinite,
              item.bounds.width > 0,
              item.bounds.height > 0 else {
            pdfView.go(to: item.page)
            return
        }
        pdfView.goToAnnotation(bounds: item.bounds, on: item.page)
    }

    private func isCommentableAnnotation(_ item: PDFAnnotationItem) -> Bool {
        switch item.id {
        case .textHighlight, .rectangleMark:
            return true
        case .documentAnnotation:
            return false
        }
    }

    private func beginAddingComment(to item: PDFAnnotationItem) {
        guard isCommentableAnnotation(item) else { return }
        editingAnnotation = item
        editingComment = nil
        annotationCommentDraft = ""
        isAnnotationCommentEditorPresented = true
    }

    private func beginEditingComment(_ comment: AnnotationComment, on item: PDFAnnotationItem) {
        guard isCommentableAnnotation(item) else { return }
        editingAnnotation = item
        editingComment = comment
        annotationCommentDraft = comment.content
        isAnnotationCommentEditorPresented = true
    }

    @ViewBuilder
    private func annotationContextMenu(for item: PDFAnnotationItem) -> some View {
        if isCommentableAnnotation(item) {
            HStack(spacing: 8) {
                ForEach(ZoteroAnnotationColor.allCases) { color in
                    Button {
                        updateColor(of: item, to: color)
                    } label: {
                        Circle()
                            .fill(annotationColor(color, for: item))
                            .frame(width: 15, height: 15)
                            .overlay {
                                Circle()
                                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                    .accessibilityLabel(Text(color.title))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .accessibilityLabel("Change Color")

            Button("Add Comment", systemImage: "text.bubble") {
                beginAddingComment(to: item)
            }

            if !item.comments.isEmpty {
                Menu("Comments", systemImage: "text.bubble.fill") {
                    ForEach(item.comments) { comment in
                        Menu {
                            Button("Edit Comment", systemImage: "pencil") {
                                beginEditingComment(comment, on: item)
                            }
                            Button("Delete Comment", systemImage: "trash", role: .destructive) {
                                deleteComment(comment)
                            }
                        } label: {
                            Text(comment.content)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Divider()
        }

        Button("Delete Annotation", systemImage: "trash", role: .destructive) {
            deleteAnnotation(item)
        }
    }

    private func annotationContextMenu(for target: PDFAnnotationItemID) -> NSMenu? {
        guard let item = annotations.first(where: { $0.id == target }) else { return nil }

        let actionTarget = PDFAnnotationMenuTarget()
        let menu = PDFAnnotationContextMenu(actionTarget: actionTarget)

        func menuItem(
            _ title: String,
            key: String,
            destructive: Bool = false,
            action: @escaping () -> Void
        ) -> NSMenuItem {
            actionTarget.actions[key] = action
            let item = NSMenuItem(
                title: title,
                action: #selector(PDFAnnotationMenuTarget.perform(_:)),
                keyEquivalent: ""
            )
            item.target = actionTarget
            item.representedObject = key
            if destructive {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            return item
        }

        if isCommentableAnnotation(item) {
            let colorPaletteItem = NSMenuItem()
            colorPaletteItem.view = PDFAnnotationColorPaletteView { color in
                updateColor(of: item, to: color)
            }
            menu.addItem(colorPaletteItem)

            menu.addItem(
                menuItem("Add Comment", key: "add-comment") {
                    beginAddingComment(to: item)
                }
            )

            if !item.comments.isEmpty {
                let commentsItem = NSMenuItem(title: "Comments", action: nil, keyEquivalent: "")
                let commentsMenu = NSMenu(title: "Comments")
                for comment in item.comments {
                    let commentItem = NSMenuItem(
                        title: String(comment.content.prefix(48)),
                        action: nil,
                        keyEquivalent: ""
                    )
                    let commentMenu = NSMenu(title: "Comment")
                    commentMenu.addItem(
                        menuItem("Edit Comment", key: "edit-comment-\(comment.id.uuidString)") {
                            beginEditingComment(comment, on: item)
                        }
                    )
                    commentMenu.addItem(
                        menuItem(
                            "Delete Comment",
                            key: "delete-comment-\(comment.id.uuidString)",
                            destructive: true
                        ) {
                            deleteComment(comment)
                        }
                    )
                    commentItem.submenu = commentMenu
                    commentsMenu.addItem(commentItem)
                }
                commentsItem.submenu = commentsMenu
                menu.addItem(commentsItem)
            }

            menu.addItem(.separator())
        }

        menu.addItem(
            menuItem("Delete Annotation", key: "delete-annotation", destructive: true) {
                deleteAnnotation(item)
            }
        )
        return menu
    }

    private func saveAnnotationComment() {
        guard let editingAnnotation else { return }
        let annotationID: UUID
        switch editingAnnotation.id {
        case .textHighlight(let id), .rectangleMark(let id):
            annotationID = id
        case .documentAnnotation:
            return
        }

        let error: String?
        if let editingComment {
            error = viewModel.updateAnnotationComment(
                editingComment.id,
                content: annotationCommentDraft,
                attachmentID: request.attachmentID,
                in: request.itemID
            )
        } else {
            error = viewModel.createAnnotationComment(
                AnnotationCommentDraft(content: annotationCommentDraft),
                for: annotationID,
                attachmentID: request.attachmentID,
                in: request.itemID
            )
        }

        if error == nil {
            do {
                annotationComments = try viewModel.annotationComments(
                    for: request.attachmentID,
                    in: request.itemID
                )
                refreshAnnotations()
                isAnnotationCommentEditorPresented = false
                return
            } catch {
                annotationError = error.localizedDescription
                return
            }
        }
        annotationError = error
    }

    private func deleteComment(_ comment: AnnotationComment) {
        guard let error = viewModel.deleteAnnotationComment(
            comment.id,
            attachmentID: request.attachmentID,
            in: request.itemID
        ) else {
            annotationComments.removeAll { $0.id == comment.id }
            refreshAnnotations()
            return
        }
        annotationError = error
    }

    private func annotationColor(_ color: ZoteroAnnotationColor, for item: PDFAnnotationItem) -> Color {
        let value: TextHighlightColor
        switch item.id {
        case .textHighlight:
            value = color.highlightColor
        case .rectangleMark, .documentAnnotation:
            value = color.borderColor
        }
        return Color(
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.alpha
        )
    }

    private func updateColor(of item: PDFAnnotationItem, to color: ZoteroAnnotationColor) {
        guard let document else { return }
        switch item.id {
        case .textHighlight(let id):
            do {
                let highlight = try viewModel.updateTextHighlightColor(
                    color.highlightColor,
                    for: id,
                    attachmentID: request.attachmentID,
                    in: request.itemID
                )
                removeRenderedAnnotation(prefix: PDFTextHighlightRenderer.annotationUserNamePrefix, id: id)
                try PDFTextHighlightRenderer.apply(highlight, to: document)
                refreshPDFAnnotationDisplay()
                textHighlights.removeAll { $0.id == id }
                textHighlights.append(highlight)
                refreshAnnotations()
            } catch {
                annotationError = error.localizedDescription
            }

        case .rectangleMark(let id):
            do {
                let mark = try viewModel.updateRectangleMarkColor(
                    color.borderColor,
                    for: id,
                    attachmentID: request.attachmentID,
                    in: request.itemID
                )
                removeRenderedAnnotation(prefix: PDFRectangleMarkRenderer.annotationUserNamePrefix, id: id)
                try PDFRectangleMarkRenderer.apply(mark, to: document)
                refreshPDFAnnotationDisplay()
                rectangleMarks.removeAll { $0.id == id }
                rectangleMarks.append(mark)
                refreshAnnotations()
            } catch {
                annotationError = error.localizedDescription
            }

        case .documentAnnotation:
            break
        }
    }

    private func deleteAnnotation(_ item: PDFAnnotationItem) {
        switch item.id {
        case .documentAnnotation:
            if let annotation = item.annotation {
                item.page.removeAnnotation(annotation)
                refreshAnnotations()
            }

        case .textHighlight(let id):
            guard let error = viewModel.deleteTextHighlight(
                id,
                attachmentID: request.attachmentID,
                in: request.itemID
            ) else {
                removeRenderedAnnotation(prefix: PDFTextHighlightRenderer.annotationUserNamePrefix, id: id)
                textHighlights.removeAll { $0.id == id }
                annotationComments.removeAll { $0.annotationID == id }
                refreshAnnotations()
                return
            }
            annotationError = error

        case .rectangleMark(let id):
            guard let error = viewModel.deleteRectangleMark(
                id,
                attachmentID: request.attachmentID,
                in: request.itemID
            ) else {
                removeRenderedAnnotation(prefix: PDFRectangleMarkRenderer.annotationUserNamePrefix, id: id)
                rectangleMarks.removeAll { $0.id == id }
                annotationComments.removeAll { $0.annotationID == id }
                refreshAnnotations()
                return
            }
            annotationError = error
        }
    }

    private func removeRenderedAnnotation(prefix: String, id: UUID) {
        guard let document else { return }
        let userName = "\(prefix)\(id.uuidString)"
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.userName == userName {
                page.removeAnnotation(annotation)
            }
        }
    }

    private func refreshAnnotations() {
        guard let document else {
            annotations = []
            return
        }
        annotations = extractAnnotations(
            from: document,
            including: textHighlights,
            rectangleMarks: rectangleMarks,
            comments: annotationComments
        )
    }

    private func refreshPDFAnnotationDisplay() {
        guard let pdfView else { return }
        pdfView.needsDisplay = true
        pdfView.documentView?.needsDisplay = true
        pdfView.displayIfNeeded()
        pdfView.documentView?.displayIfNeeded()
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
                    isRectangleToolActive: isRectangleToolActive,
                    onCreateHighlight: { draft in
                        try viewModel.createTextHighlight(
                            draft,
                            for: request.attachmentID,
                            in: request.itemID
                        )
                    },
                    onCreateRectangleMark: { draft in
                        try viewModel.createRectangleMark(
                            draft,
                            for: request.attachmentID,
                            in: request.itemID
                        )
                    },
                    onHighlightsChanged: { highlight in
                        textHighlights.removeAll { $0.id == highlight.id }
                        textHighlights.append(highlight)
                        refreshAnnotations()
                    },
                    onRectangleMarkCreated: { mark in
                        rectangleMarks.append(mark)
                        refreshAnnotations()
                    },
                    onAnnotationError: { annotationError = $0 },
                    onAnnotationClicked: { target in
                        selectedAnnotationID = target
                        selectedSidebarTab = .annotations
                    },
                    onAnnotationMenuRequested: { target in
                        annotationContextMenu(for: target)
                    },
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
        .alert(
            "PDF Annotation Error",
            isPresented: Binding(
                get: { annotationError != nil },
                set: { if !$0 { annotationError = nil } }
            )
        ) {
            Button("OK") { annotationError = nil }
        } message: {
            Text(annotationError ?? "Please try again.")
        }
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
    let currentPageIndex: Int

    func makeNSView(context: Context) -> AutoSizingPDFThumbnailView {
        let view = AutoSizingPDFThumbnailView()
        view.pdfView = pdfView
        view.maximumNumberOfColumns = 1
        view.allowsDragging = false
        view.allowsMultipleSelection = false
        view.backgroundColor = .clear
        view.synchronize(with: pdfView, currentPageIndex: currentPageIndex)
        return view
    }

    func updateNSView(_ view: AutoSizingPDFThumbnailView, context: Context) {
        view.synchronize(with: pdfView, currentPageIndex: currentPageIndex)
    }
}

private final class AutoSizingPDFThumbnailView: PDFThumbnailView {
    private var synchronizedPageIndex: Int?

    override func layout() {
        super.layout()
        updateThumbnailSize()
    }

    func synchronize(with pdfView: PDFView, currentPageIndex: Int) {
        if self.pdfView !== pdfView {
            self.pdfView = pdfView
            synchronizedPageIndex = nil
        }

        guard let currentPage = pdfView.currentPage,
              let document = pdfView.document,
              document.index(for: currentPage) == currentPageIndex else {
            needsLayout = true
            return
        }

        if synchronizedPageIndex != currentPageIndex {
            // Rebinding makes PDFKit recompute the single selected thumbnail
            // after the PDFView finishes restoring its initial position.
            self.pdfView = nil
            self.pdfView = pdfView
            synchronizedPageIndex = currentPageIndex
        }
        needsLayout = true
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

private enum PDFTextHighlightGeometryBuilder {
    static func makeDraft(from selection: PDFSelection, in document: PDFDocument) throws -> TextHighlightDraft {
        guard let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            throw PDFTextHighlightError.emptySelection
        }

        var pages: [TextHighlightPage] = []
        for page in selection.pages {
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            let rectangles = rectangles(in: selection, on: page)
            guard !rectangles.isEmpty else { continue }
            pages.append(TextHighlightPage(pageIndex: pageIndex, rectangles: rectangles))
        }

        guard !pages.isEmpty else {
            throw PDFTextHighlightError.missingGeometry
        }
        return TextHighlightDraft(selectedText: selectedText, pages: pages)
    }

    static func recoveredPages(for highlight: TextHighlight, in document: PDFDocument) -> [TextHighlightPage]? {
        let matches = document.findString(highlight.selectedText, withOptions: [])
        guard !matches.isEmpty else { return nil }

        var recoveredPages: [TextHighlightPage] = []
        for storedPage in highlight.pages {
            guard let page = document.page(at: storedPage.pageIndex) else { return nil }
            let candidates = matches.compactMap { selection -> [TextHighlightRectangle]? in
                guard selection.pages.contains(where: { document.index(for: $0) == storedPage.pageIndex }) else {
                    return nil
                }
                let rectangles = rectangles(in: selection, on: page)
                return rectangles.isEmpty ? nil : rectangles
            }
            guard let nearest = candidates.min(by: {
                distance(from: $0, to: storedPage.rectangles) < distance(from: $1, to: storedPage.rectangles)
            }) else {
                return nil
            }
            recoveredPages.append(TextHighlightPage(pageIndex: storedPage.pageIndex, rectangles: nearest))
        }
        return recoveredPages.sorted { $0.pageIndex < $1.pageIndex }
    }

    private static func rectangles(in selection: PDFSelection, on page: PDFPage) -> [TextHighlightRectangle] {
        selection.selectionsByLine().compactMap { lineSelection in
            guard lineSelection.pages.contains(where: { $0 === page }) else { return nil }
            let rect = lineSelection.bounds(for: page).standardized
            guard rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite,
                  rect.width > 0,
                  rect.height > 0 else {
                return nil
            }
            return TextHighlightRectangle(
                x: Double(rect.minX),
                y: Double(rect.minY),
                width: Double(rect.width),
                height: Double(rect.height)
            )
        }
        .sorted {
            if abs($0.y - $1.y) > 0.5 { return $0.y > $1.y }
            return $0.x < $1.x
        }
    }

    private static func distance(
        from lhs: [TextHighlightRectangle],
        to rhs: [TextHighlightRectangle]
    ) -> Double {
        guard let lhsBounds = bounds(of: lhs), let rhsBounds = bounds(of: rhs) else { return .infinity }
        return hypot(lhsBounds.midX - rhsBounds.midX, lhsBounds.midY - rhsBounds.midY)
    }

    private static func bounds(of rectangles: [TextHighlightRectangle]) -> CGRect? {
        guard let first = rectangles.first else { return nil }
        return rectangles.dropFirst().reduce(
            CGRect(x: first.x, y: first.y, width: first.width, height: first.height)
        ) { result, rectangle in
            result.union(CGRect(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: rectangle.height))
        }
    }
}

private enum PDFTextHighlightRenderer {
    static let annotationUserNamePrefix = "Refolio.TextHighlight."

    static func apply(_ highlight: TextHighlight, to document: PDFDocument) throws {
        var pendingAnnotations: [(PDFPage, PDFAnnotation)] = []

        for pageGeometry in highlight.pages {
            guard let page = document.page(at: pageGeometry.pageIndex) else {
                throw PDFTextHighlightError.pageUnavailable
            }
            let rectangles = pageGeometry.rectangles.compactMap { geometry -> CGRect? in
                let rect = CGRect(
                    x: CGFloat(geometry.x),
                    y: CGFloat(geometry.y),
                    width: CGFloat(geometry.width),
                    height: CGFloat(geometry.height)
                )
                guard rect.origin.x.isFinite,
                      rect.origin.y.isFinite,
                      rect.width.isFinite,
                      rect.height.isFinite,
                      rect.width > 0,
                      rect.height > 0 else {
                    return nil
                }
                return rect
            }
            guard !rectangles.isEmpty else {
                throw PDFTextHighlightError.missingGeometry
            }

            let bounds = rectangles.dropFirst().reduce(rectangles[0]) { $0.union($1) }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = NSColor(
                srgbRed: CGFloat(highlight.color.red),
                green: CGFloat(highlight.color.green),
                blue: CGFloat(highlight.color.blue),
                alpha: CGFloat(highlight.color.alpha)
            )
            annotation.userName = "\(annotationUserNamePrefix)\(highlight.id.uuidString)"
            annotation.quadrilateralPoints = rectangles.flatMap { rect in
                [
                    NSValue(point: CGPoint(x: rect.minX - bounds.minX, y: rect.maxY - bounds.minY)),
                    NSValue(point: CGPoint(x: rect.maxX - bounds.minX, y: rect.maxY - bounds.minY)),
                    NSValue(point: CGPoint(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY)),
                    NSValue(point: CGPoint(x: rect.maxX - bounds.minX, y: rect.minY - bounds.minY))
                ]
            }
            pendingAnnotations.append((page, annotation))
        }

        guard !pendingAnnotations.isEmpty else {
            throw PDFTextHighlightError.missingGeometry
        }
        for (page, annotation) in pendingAnnotations {
            page.addAnnotation(annotation)
        }
    }
}

private enum PDFTextHighlightError: LocalizedError {
    case emptySelection
    case missingGeometry
    case pageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Select text in the PDF and try again."
        case .missingGeometry:
            "PDFKit could not map the selected text to a highlight area. Please select it again."
        case .pageUnavailable:
            "A page containing this highlight is no longer available."
        }
    }
}

private enum PDFRectangleMarkRenderer {
    static let annotationUserNamePrefix = "Refolio.RectangleMark."

    static func apply(_ mark: RectangleMark, to document: PDFDocument) throws {
        guard let page = document.page(at: mark.pageIndex) else {
            throw PDFRectangleMarkError.pageUnavailable
        }
        let bounds = CGRect(x: mark.x, y: mark.y, width: mark.width, height: mark.height).standardized
        guard isValid(bounds) else {
            throw PDFRectangleMarkError.invalidGeometry
        }

        let userName = "\(annotationUserNamePrefix)\(mark.id.uuidString)"
        guard !page.annotations.contains(where: { $0.userName == userName }) else { return }
        page.addAnnotation(makeAnnotation(bounds: bounds, color: mark.color, userName: userName))
    }

    static func makeAnnotation(
        bounds: CGRect,
        color: TextHighlightColor = ZoteroAnnotationColor.blue.borderColor,
        userName: String
    ) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        annotation.userName = userName
        annotation.contents = nil
        annotation.color = NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        annotation.interiorColor = NSColor.clear

        let border = PDFBorder()
        border.lineWidth = 2
        annotation.border = border
        return annotation
    }

    static func isValid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.width.isFinite
            && bounds.height.isFinite
            && bounds.width > 0
            && bounds.height > 0
    }
}

private enum PDFRectangleMarkError: LocalizedError {
    case invalidGeometry
    case pageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidGeometry:
            "The rectangle annotation has invalid page geometry."
        case .pageUnavailable:
            "The page containing this rectangle annotation is no longer available."
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let initialPosition: PDFReadingPosition?
    let translationViewModel: TranslationViewModel
    let onOpenDetailPanel: () -> Void
    let isRectangleToolActive: Bool
    let onCreateHighlight: (TextHighlightDraft) throws -> TextHighlight
    let onCreateRectangleMark: (RectangleMarkDraft) throws -> RectangleMark
    let onHighlightsChanged: (TextHighlight) -> Void
    let onRectangleMarkCreated: (RectangleMark) -> Void
    let onAnnotationError: (String) -> Void
    let onAnnotationClicked: (PDFAnnotationItemID) -> Void
    let onAnnotationMenuRequested: (PDFAnnotationItemID) -> NSMenu?
    let onPositionChanged: (PDFReadingPosition) -> Void
    let onCurrentPageChanged: (Int) -> Void
    let onViewReady: (ReadingPDFView?) -> Void

    func makeNSView(context: Context) -> ReadingPDFView {
        let view = ReadingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        view.isRectangleDrawingEnabled = isRectangleToolActive
        view.onCreateRectangleMark = onCreateRectangleMark
        view.onRectangleMarkCreated = onRectangleMarkCreated
        view.onAnnotationError = onAnnotationError
        view.onAnnotationClicked = onAnnotationClicked
        view.onAnnotationMenuRequested = onAnnotationMenuRequested
        context.coordinator.observe(view)
        context.coordinator.onCurrentPageChanged = onCurrentPageChanged
        context.coordinator.translationViewModel = translationViewModel
        context.coordinator.onOpenDetailPanel = onOpenDetailPanel
        context.coordinator.onCreateHighlight = onCreateHighlight
        context.coordinator.onHighlightsChanged = onHighlightsChanged
        context.coordinator.onPositionChanged = onPositionChanged
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
        context.coordinator.onCreateHighlight = onCreateHighlight
        context.coordinator.onHighlightsChanged = onHighlightsChanged
        view.isRectangleDrawingEnabled = isRectangleToolActive
        view.onCreateRectangleMark = onCreateRectangleMark
        view.onRectangleMarkCreated = onRectangleMarkCreated
        view.onAnnotationError = onAnnotationError
        view.onAnnotationClicked = onAnnotationClicked
        view.onAnnotationMenuRequested = onAnnotationMenuRequested
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
            onCreateHighlight: onCreateHighlight,
            onHighlightsChanged: onHighlightsChanged,
            onPositionChanged: onPositionChanged,
            onCurrentPageChanged: onCurrentPageChanged,
            onViewReady: onViewReady
        )
    }

    private func restorePosition(in view: ReadingPDFView, coordinator: Coordinator) {
        coordinator.isReadyToSave = false
        view.autoScales = true

        guard let initialPosition else {
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
        guard let document = view.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            coordinator.finishInitialRestore()
            return
        }

        view.autoScales = true
        view.layoutDocumentView()
        if let pointY = position.pointY, pointY.isFinite {
            let destination = PDFDestination(
                page: page,
                at: CGPoint(x: kPDFDestinationUnspecifiedValue, y: CGFloat(pointY))
            )
            view.go(to: destination)
        } else {
            view.go(to: page)
        }
        coordinator.finishInitialRestore()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var isReadyToSave: Bool = false
        var translationViewModel: TranslationViewModel
        var onOpenDetailPanel: () -> Void
        var onCreateHighlight: (TextHighlightDraft) throws -> TextHighlight
        var onHighlightsChanged: (TextHighlight) -> Void
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
            onCreateHighlight: @escaping (TextHighlightDraft) throws -> TextHighlight,
            onHighlightsChanged: @escaping (TextHighlight) -> Void,
            onPositionChanged: @escaping (PDFReadingPosition) -> Void,
            onCurrentPageChanged: @escaping (Int) -> Void,
            onViewReady: @escaping (ReadingPDFView?) -> Void
        ) {
            self.translationViewModel = translationViewModel
            self.onOpenDetailPanel = onOpenDetailPanel
            self.onCreateHighlight = onCreateHighlight
            self.onHighlightsChanged = onHighlightsChanged
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

        func finishInitialRestore() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReadyToSave = true
                self.reportCurrentPage()
            }
        }

        func closePopover() {
            popover?.close()
            popover = nil
        }

        @objc private func selectionChanged(_ notification: Notification) {
            guard let view = pdfView else { return }
            if (view as? ReadingPDFView)?.isRectangleDrawingEnabled == true {
                popover?.close()
                return
            }
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
                    onHighlight: { [weak self] in
                        guard let self else { return "The selection is no longer available." }
                        return self.createHighlightForCurrentSelection()
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

        private func createHighlightForCurrentSelection() -> String? {
            guard let view = pdfView,
                  let document = view.document,
                  let selection = view.currentSelection else {
                return "Select text in the PDF and try again."
            }
            do {
                let draft = try PDFTextHighlightGeometryBuilder.makeDraft(
                    from: selection,
                    in: document
                )
                let highlight = try onCreateHighlight(draft)
                try PDFTextHighlightRenderer.apply(highlight, to: document)
                onHighlightsChanged(highlight)
                return nil
            } catch {
                return error.localizedDescription
            }
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
    private weak var rectanglePage: PDFPage?
    private var rectanglePageIndex: Int?
    private var rectangleStartPoint: CGPoint?
    private var rectanglePreview: PDFAnnotation?

    var isRectangleDrawingEnabled = false {
        didSet {
            guard oldValue != isRectangleDrawingEnabled else { return }
            if !isRectangleDrawingEnabled {
                cancelRectangleDrawing()
            }
            window?.invalidateCursorRects(for: self)
        }
    }

    var onCreateRectangleMark: ((RectangleMarkDraft) throws -> RectangleMark)?
    var onRectangleMarkCreated: ((RectangleMark) -> Void)?
    var onAnnotationError: ((String) -> Void)?
    var onAnnotationClicked: ((PDFAnnotationItemID) -> Void)?
    var onAnnotationMenuRequested: ((PDFAnnotationItemID) -> NSMenu?)?

    override func resetCursorRects() {
        super.resetCursorRects()
        if isRectangleDrawingEnabled {
            addCursorRect(visibleRect, cursor: .crosshair)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let target = annotationTarget(at: event) {
            // Never fall back to PDFKit's document menu on an annotation.
            // The annotation callback may intentionally return nil while the
            // SwiftUI state is changing, and that should still suppress the
            // native PDF menu for this event.
            return onAnnotationMenuRequested?(target)
        }
        return super.menu(for: event)
    }

    private func annotationTarget(at event: NSEvent) -> PDFAnnotationItemID? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: false) else { return nil }
        let pagePoint = convert(viewPoint, to: page)

        for annotation in page.annotations.reversed() {
            guard annotation.bounds.contains(pagePoint) else { continue }
            if let userName = annotation.userName,
               userName.hasPrefix(PDFTextHighlightRenderer.annotationUserNamePrefix),
               let id = UUID(uuidString: String(userName.dropFirst(PDFTextHighlightRenderer.annotationUserNamePrefix.count))) {
                return .textHighlight(id)
            }
            if let userName = annotation.userName,
               userName.hasPrefix(PDFRectangleMarkRenderer.annotationUserNamePrefix),
               let id = UUID(uuidString: String(userName.dropFirst(PDFRectangleMarkRenderer.annotationUserNamePrefix.count))) {
                return .rectangleMark(id)
            }
            if annotation.type != "Link", annotation.type != "Widget" {
                return .documentAnnotation(ObjectIdentifier(annotation))
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isRectangleDrawingEnabled else {
            if let target = annotationTarget(at: event) {
                onAnnotationClicked?(target)
            }
            super.mouseDown(with: event)
            return
        }

        cancelRectangleDrawing()
        clearSelection()
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let document,
              let page = page(for: viewPoint, nearest: false),
              let pagePoint = pagePoint(viewPoint, on: page) else {
            return
        }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return }

        rectanglePage = page
        rectanglePageIndex = pageIndex
        rectangleStartPoint = pagePoint
    }

    override func mouseDragged(with event: NSEvent) {
        guard isRectangleDrawingEnabled else {
            super.mouseDragged(with: event)
            return
        }
        guard rectanglePage != nil else { return }
        updateRectanglePreview(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isRectangleDrawingEnabled else {
            super.mouseUp(with: event)
            return
        }

        updateRectanglePreview(at: event)
        guard let page = rectanglePage,
              let pageIndex = rectanglePageIndex,
              let preview = rectanglePreview else {
            cancelRectangleDrawing()
            return
        }

        let bounds = preview.bounds.standardized
        guard bounds.width >= 2, bounds.height >= 2,
              let onCreateRectangleMark else {
            page.removeAnnotation(preview)
            cancelRectangleDrawing()
            return
        }

        let draft = RectangleMarkDraft(
            pageIndex: pageIndex,
            x: Double(bounds.minX),
            y: Double(bounds.minY),
            width: Double(bounds.width),
            height: Double(bounds.height)
        )

        do {
            let mark = try onCreateRectangleMark(draft)
            preview.userName = "\(PDFRectangleMarkRenderer.annotationUserNamePrefix)\(mark.id.uuidString)"
            onRectangleMarkCreated?(mark)
            clearRectangleDrawingState()
        } catch {
            page.removeAnnotation(preview)
            onAnnotationError?(error.localizedDescription)
            clearRectangleDrawingState()
        }
    }

    private func updateRectanglePreview(at event: NSEvent) {
        guard let page = rectanglePage,
              let startPoint = rectangleStartPoint else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let endPoint = pagePoint(viewPoint, on: page) else { return }
        let bounds = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        ).standardized

        if rectanglePreview == nil {
            guard bounds.width >= 2, bounds.height >= 2 else { return }
            let preview = PDFRectangleMarkRenderer.makeAnnotation(
                bounds: bounds,
                userName: "\(PDFRectangleMarkRenderer.annotationUserNamePrefix)Draft"
            )
            page.addAnnotation(preview)
            rectanglePreview = preview
        } else {
            rectanglePreview?.bounds = bounds
        }
        needsDisplay = true
    }

    private func pagePoint(_ pointInView: CGPoint, on page: PDFPage) -> CGPoint? {
        let pageBounds = page.bounds(for: .cropBox).standardized
        guard PDFRectangleMarkRenderer.isValid(pageBounds) else { return nil }
        let point = convert(pointInView, to: page)
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(
            x: min(max(point.x, pageBounds.minX), pageBounds.maxX),
            y: min(max(point.y, pageBounds.minY), pageBounds.maxY)
        )
    }

    private func cancelRectangleDrawing() {
        if let rectanglePage, let rectanglePreview {
            rectanglePage.removeAnnotation(rectanglePreview)
            needsDisplay = true
        }
        clearRectangleDrawingState()
    }

    private func clearRectangleDrawingState() {
        rectanglePage = nil
        rectanglePageIndex = nil
        rectangleStartPoint = nil
        rectanglePreview = nil
    }

    func goToAnnotation(bounds: CGRect, on page: PDFPage) {
        go(to: bounds, on: page)
        let annotationCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        afterLayout { [weak self, weak page] in
            guard let self,
                  let page,
                  let clipView = firstClipView(in: self),
                  let documentView = clipView.documentView else { return }

            let pointInPDFView = self.convert(annotationCenter, from: page)
            let pointInDocument = documentView.convert(pointInPDFView, from: self)
            let visibleRect = clipView.documentVisibleRect
            guard pointInDocument.y.isFinite, visibleRect.height > 0 else { return }

            clipView.scroll(to: NSPoint(
                x: visibleRect.minX,
                y: pointInDocument.y - visibleRect.height / 2
            ))
            clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        }
    }

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

    private func firstClipView(in view: NSView) -> NSClipView? {
        if let clipView = view as? NSClipView, clipView.documentView != nil {
            return clipView
        }
        for subview in view.subviews {
            if let clipView = firstClipView(in: subview) {
                return clipView
            }
        }
        return nil
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
                    self?.updateCenterOffset()
                }
            }
        }

        NotificationCenter.default.removeObserver(self, name: NSSplitView.didResizeSubviewsNotification, object: splitView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSplitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )

        updateCenterOffset()
    }

    @objc private func handleSplitViewDidResize() {
        updateCenterOffset()
    }

    private func updateCenterOffset() {
        guard let splitVC, splitVC.splitViewItems.count >= 3 else { return }
        let items = splitVC.splitViewItems
        let leftWidth: CGFloat = items[0].isCollapsed ? 0 : items[0].viewController.view.frame.width
        let rightWidth: CGFloat = items[2].isCollapsed ? 0 : items[2].viewController.view.frame.width

        DispatchQueue.main.async { [weak self] in
            guard let self, let state = self.splitViewState else { return }
            if abs(state.sidebarWidth - leftWidth) > 0.5 {
                state.sidebarWidth = leftWidth
            }
            if abs(state.detailWidth - rightWidth) > 0.5 {
                state.detailWidth = rightWidth
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
