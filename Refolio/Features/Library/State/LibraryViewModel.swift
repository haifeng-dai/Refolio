import Foundation
import Observation

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

    func addItem(_ item: LibraryItem, to folder: LibraryFolder) -> String? {
        do {
            try workflow.addItem(item.id, to: folder.id)
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
