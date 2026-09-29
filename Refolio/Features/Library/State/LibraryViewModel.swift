import Foundation
import Observation

enum MainWorkspaceMode: String, CaseIterable, Identifiable {
    case library
    case reader

    var id: Self { self }
}

@MainActor
@Observable
final class LibraryViewModel {
    private let workflow: ItemLibraryWorkflow

    private(set) var items: [LibraryItem] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var notesByItemID: [UUID: [LiteratureNote]] = [:]
    var searchText = ""
    var selectedFolder: FolderSelection? = .allItems
    var attachmentFilter: ItemAttachmentFilter = .all
    private(set) var loadError: String?

    var workspaceMode: MainWorkspaceMode = .library
    var openDocuments: [PDFReaderRequest] = []
    var activeDocumentAttachmentID: UUID?
    var selectedItemIDs: Set<UUID> = []
    var focusedItemID: UUID?

    var activeReaderRequest: PDFReaderRequest? {
        guard let activeID = activeDocumentAttachmentID else {
            return openDocuments.last
        }
        return openDocuments.first(where: { $0.attachmentID == activeID }) ?? openDocuments.last
    }

    var activeReaderTitle: String? {
        guard let request = activeReaderRequest else { return nil }
        return title(for: request)
    }

    func title(for request: PDFReaderRequest) -> String {
        items.first(where: { $0.id == request.itemID })?.title ?? "Document"
    }

    func openInReader(itemID: UUID, attachmentID: UUID) {
        let request = PDFReaderRequest(itemID: itemID, attachmentID: attachmentID)
        if !openDocuments.contains(request) {
            openDocuments.append(request)
        }
        activeDocumentAttachmentID = attachmentID
        workspaceMode = .reader
    }

    func selectDocument(_ request: PDFReaderRequest) {
        activeDocumentAttachmentID = request.attachmentID
        workspaceMode = .reader
    }

    func closeDocument(_ request: PDFReaderRequest) {
        guard let index = openDocuments.firstIndex(of: request) else { return }
        let isClosingActive = (activeDocumentAttachmentID == request.attachmentID)
        openDocuments.remove(at: index)

        if openDocuments.isEmpty {
            activeDocumentAttachmentID = nil
            workspaceMode = .library
        } else if isClosingActive {
            let newIndex = min(index, openDocuments.count - 1)
            activeDocumentAttachmentID = openDocuments[newIndex].attachmentID
        }
    }

    func switchToReader() {
        if openDocuments.isEmpty,
           selectedItemIDs.count == 1,
           let selectedID = focusedItemID,
           let selected = items.first(where: { $0.id == selectedID }),
           let mainAttachment = selected.attachments.first(where: { $0.role == .main }) {
            openInReader(itemID: selected.id, attachmentID: mainAttachment.id)
        } else {
            workspaceMode = .reader
        }
    }

    func updateSelectedItemIDs(_ itemIDs: Set<UUID>) {
        let visibleItems = filteredItems
        let visibleItemIDs = Set(visibleItems.map(\.id))
        let selection = itemIDs.intersection(visibleItemIDs)
        let newlySelectedIDs = selection.subtracting(selectedItemIDs)

        selectedItemIDs = selection

        if let newlyFocusedItem = visibleItems.last(where: { newlySelectedIDs.contains($0.id) }) {
            focusedItemID = newlyFocusedItem.id
        } else if let focusedItemID, !selection.contains(focusedItemID) {
            self.focusedItemID = visibleItems.first(where: { selection.contains($0.id) })?.id
        }
    }

    func reconcileSelection(visibleItemIDs: [UUID]) {
        let visibleIDs = Set(visibleItemIDs)
        let selection = selectedItemIDs.intersection(visibleIDs)

        if !selection.isEmpty {
            selectedItemIDs = selection
            if let focusedItemID, !selection.contains(focusedItemID) {
                self.focusedItemID = visibleItemIDs.first(where: { selection.contains($0) })
            }
            return
        }

        if let firstVisibleItemID = visibleItemIDs.first {
            selectedItemIDs = [firstVisibleItemID]
            focusedItemID = firstVisibleItemID
        } else {
            selectedItemIDs = []
            focusedItemID = nil
        }
    }

    func selectOnlyItem(_ itemID: UUID?) {
        selectedItemIDs = itemID.map { [$0] } ?? []
        focusedItemID = itemID
    }

    func focusItem(_ itemID: UUID) {
        if !selectedItemIDs.contains(itemID) {
            selectedItemIDs = [itemID]
        }
        focusedItemID = itemID
    }

    func showItemInLibrary(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else {
            selectOnlyItem(nil)
            workspaceMode = .library
            return
        }

        if !filteredItems.contains(where: { $0.id == itemID }) {
            selectedFolder = item.isTrashed ? .trash : .allItems
            attachmentFilter = .all
            searchText = ""
        }
        selectOnlyItem(itemID)
        workspaceMode = .library
    }

    init(workflow: ItemLibraryWorkflow) {
        self.workflow = workflow
    }

    var filteredItems: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let inFolder = items.filter { item in
            switch selectedFolder ?? .allItems {
            case .allItems:
                !item.isTrashed
            case .unfiled:
                !item.isTrashed && item.folderIDs.isEmpty
            case .trash:
                item.isTrashed
            case let .folder(folderID):
                !item.isTrashed && item.folderIDs.contains(folderID)
            }
        }

        let inAttachmentFilter = inFolder.filter { item in
            switch attachmentFilter {
            case .all:
                true
            case .hasMainFile:
                item.hasMainAttachment
            case .missingMainFile:
                !item.hasMainAttachment
            }
        }

        guard !query.isEmpty else { return inAttachmentFilter }
        return inAttachmentFilter.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || (item.doi?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.publicationTitle?.localizedCaseInsensitiveContains(query) ?? false)
                || item.authorNames.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func load() {
        do {
            items = try workflow.fetchItems()
            folders = try workflow.fetchFolders()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func clearLoadError() {
        loadError = nil
    }

    func lookupDOI(_ rawDOI: String) async -> Result<ItemDraft, Error> {
        do {
            let draft = try await workflow.lookupDOI(rawDOI)
            return .success(draft)
        } catch {
            return .failure(error)
        }
    }

    func lookupDOIMetadata(_ rawDOI: String) async -> Result<DOIMetadata, Error> {
        do {
            let metadata = try await workflow.lookupDOIMetadata(rawDOI)
            return .success(metadata)
        } catch {
            return .failure(error)
        }
    }

    func prepareDOIUpdate(
        for item: LibraryItem,
        remote: DOIMetadata
    ) -> Result<DOIUpdatePreview, Error> {
        do {
            return .success(try workflow.prepareDOIUpdate(for: item, remote: remote))
        } catch {
            return .failure(error)
        }
    }

    func applyDOIUpdate(_ plan: DOIUpdatePlan) -> String? {
        do {
            try workflow.updateItemByDOI(plan)
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func createItem(_ draft: ItemDraft) -> String? {
        do {
            let folderID: UUID?
            if case let .folder(id) = selectedFolder {
                folderID = id
            } else {
                folderID = nil
            }
            _ = try workflow.createItem(from: draft, in: folderID)
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateItem(_ itemID: UUID, from draft: ItemDraft) -> String? {
        do {
            try workflow.updateItem(itemID, from: draft)
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func createFolder(named name: String) -> String? {
        do {
            let folder = try workflow.createFolder(named: name)
            selectedFolder = .folder(folder.id)
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func addItems(_ itemIDs: Set<UUID>, to folder: LibraryFolder) -> String? {
        do {
            try workflow.addItems(itemIDs, to: folder.id)
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func moveToTrash(_ item: LibraryItem) -> String? {
        updateTrashState(of: item, restore: false)
    }

    func restore(_ item: LibraryItem) -> String? {
        updateTrashState(of: item, restore: true)
    }

    func importAttachment(from url: URL, role: AttachmentRole, to itemID: UUID) async -> String? {
        do {
            try await workflow.importAttachment(
                from: url,
                originalFileName: url.lastPathComponent,
                role: role,
                to: itemID
            )
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func openAttachment(_ attachmentID: UUID, for itemID: UUID) async throws -> AttachmentOpenDisposition {
        try await workflow.openAttachment(attachmentID, for: itemID)
    }

    func pdfDocument(_ attachmentID: UUID, for itemID: UUID) async throws -> AttachmentDocument {
        try await workflow.pdfDocument(attachmentID, for: itemID)
    }

    func saveReadingPosition(_ position: PDFReadingPosition, for attachmentID: UUID, in itemID: UUID) -> String? {
        do {
            try workflow.saveReadingPosition(position, for: attachmentID, in: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func notes(for itemID: UUID) -> [LiteratureNote] {
        notesByItemID[itemID] ?? []
    }

    func loadNotes(for itemID: UUID) -> String? {
        do {
            notesByItemID[itemID] = try workflow.fetchNotes(for: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func createNote(_ draft: LiteratureNoteDraft, for itemID: UUID) -> String? {
        do {
            let note = try workflow.createNote(draft, for: itemID)
            notesByItemID[itemID, default: []].append(note)
            sortNotes(for: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateNote(_ noteID: UUID, content: String, in itemID: UUID) -> String? {
        do {
            let note = try workflow.updateNote(noteID, content: content, in: itemID)
            guard let index = notesByItemID[itemID]?.firstIndex(where: { $0.id == noteID }) else {
                notesByItemID[itemID] = try workflow.fetchNotes(for: itemID)
                return nil
            }
            notesByItemID[itemID]?[index] = note
            sortNotes(for: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteNote(_ noteID: UUID, in itemID: UUID) -> String? {
        do {
            try workflow.deleteNote(noteID, in: itemID)
            notesByItemID[itemID]?.removeAll { $0.id == noteID }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func textHighlights(for attachmentID: UUID, in itemID: UUID) throws -> [TextHighlight] {
        try workflow.fetchTextHighlights(for: attachmentID, in: itemID)
    }

    func createTextHighlight(_ draft: TextHighlightDraft, for attachmentID: UUID, in itemID: UUID) throws -> TextHighlight {
        try workflow.createTextHighlight(draft, for: attachmentID, in: itemID)
    }

    func updateTextHighlightGeometry(
        _ pages: [TextHighlightPage],
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        try workflow.updateTextHighlightGeometry(
            pages,
            for: highlightID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func deleteTextHighlight(
        _ highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) -> String? {
        do {
            try workflow.deleteTextHighlight(highlightID, attachmentID: attachmentID, in: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateTextHighlightColor(
        _ color: TextHighlightColor,
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        try workflow.updateTextHighlightColor(
            color,
            for: highlightID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func rectangleMarks(for attachmentID: UUID, in itemID: UUID) throws -> [RectangleMark] {
        try workflow.fetchRectangleMarks(for: attachmentID, in: itemID)
    }

    func createRectangleMark(
        _ draft: RectangleMarkDraft,
        for attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark {
        try workflow.createRectangleMark(draft, for: attachmentID, in: itemID)
    }

    func deleteRectangleMark(
        _ markID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) -> String? {
        do {
            try workflow.deleteRectangleMark(markID, attachmentID: attachmentID, in: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateRectangleMarkColor(
        _ color: TextHighlightColor,
        for markID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark {
        try workflow.updateRectangleMarkColor(
            color,
            for: markID,
            attachmentID: attachmentID,
            in: itemID
        )
    }

    func annotationComments(for attachmentID: UUID, in itemID: UUID) throws -> [AnnotationComment] {
        try workflow.fetchAnnotationComments(for: attachmentID, in: itemID)
    }

    func createAnnotationComment(
        _ draft: AnnotationCommentDraft,
        for annotationID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) -> String? {
        do {
            _ = try workflow.createAnnotationComment(
                draft,
                for: annotationID,
                attachmentID: attachmentID,
                in: itemID
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateAnnotationComment(
        _ commentID: UUID,
        content: String,
        attachmentID: UUID,
        in itemID: UUID
    ) -> String? {
        do {
            _ = try workflow.updateAnnotationComment(
                commentID,
                content: content,
                attachmentID: attachmentID,
                in: itemID
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteAnnotationComment(
        _ commentID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) -> String? {
        do {
            try workflow.deleteAnnotationComment(
                commentID,
                attachmentID: attachmentID,
                in: itemID
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var unfiledCount: Int {
        items.filter { !$0.isTrashed && $0.folderIDs.isEmpty }.count
    }

    var trashCount: Int {
        items.filter(\.isTrashed).count
    }

    private func updateTrashState(of item: LibraryItem, restore: Bool) -> String? {
        do {
            if restore {
                try workflow.restore(item.id)
            } else {
                try workflow.moveToTrash(item.id)
            }
            load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func sortNotes(for itemID: UUID) {
        notesByItemID[itemID]?.sort { $0.updatedAt > $1.updatedAt }
    }
}
