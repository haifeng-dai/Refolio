import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private let workflow: ItemLibraryWorkflow

    private(set) var items: [LibraryItem] = []
    private(set) var folders: [LibraryFolder] = []
    var searchText = ""
    var selectedFolder: FolderSelection? = .allItems
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
        guard !query.isEmpty else { return inFolder }
        return inFolder.filter { item in
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

    func openAttachment(_ attachmentID: UUID, for itemID: UUID) async -> String? {
        do {
            try await workflow.openAttachment(attachmentID, for: itemID)
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
}
