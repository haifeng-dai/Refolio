import Foundation

@MainActor
struct ItemLibraryWorkflow {
    private let repository: any ItemRepository
    private let attachmentFileStore: any AttachmentFileStore

    init(repository: any ItemRepository, attachmentFileStore: any AttachmentFileStore) {
        self.repository = repository
        self.attachmentFileStore = attachmentFileStore
    }

    func fetchItems() throws -> [LibraryItem] {
        try repository.fetchAll()
    }

    func fetchFolders() throws -> [LibraryFolder] {
        try repository.fetchFolders()
    }

    func createItem(from draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem {
        try repository.create(normalized(draft), in: folderID)
    }

    func updateItem(_ itemID: UUID, from draft: ItemDraft) throws {
        try repository.update(itemID, from: normalized(draft))
    }

    private func normalized(_ draft: ItemDraft) throws -> ItemDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ItemDraftError.missingTitle
        }

        try validateDate(year: draft.publicationYear, month: draft.publicationMonth, day: draft.publicationDay)

        return ItemDraft(
            title: title,
            abstract: draft.abstract?.trimmedOrNil,
            doi: draft.doi?.trimmedOrNil,
            publicationYear: draft.publicationYear,
            publicationMonth: draft.publicationMonth,
            publicationDay: draft.publicationDay,
            volume: draft.volume?.trimmedOrNil,
            issue: draft.issue?.trimmedOrNil,
            pageRange: draft.pageRange?.trimmedOrNil,
            urlString: draft.urlString?.trimmedOrNil,
            authorNames: draft.authorNames.compactMap(\.trimmedOrNil),
            publicationTitle: draft.publicationTitle?.trimmedOrNil,
            literatureType: draft.literatureType?.trimmedOrNil
        )
    }

    func createFolder(named name: String) throws -> LibraryFolder {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FolderNameError.empty }
        return try repository.createFolder(named: name)
    }

    func addItem(_ itemID: UUID, to folderID: UUID) throws {
        try repository.add(itemID, to: folderID)
    }

    func moveToTrash(_ itemID: UUID) throws {
        try repository.moveToTrash(itemID)
    }

    func restore(_ itemID: UUID) throws {
        try repository.restore(itemID)
    }

    func importAttachment(from sourceURL: URL, originalFileName: String, role: AttachmentRole, to itemID: UUID) async throws {
        let attachmentID = UUID()
        let file = try await attachmentFileStore.copy(
            from: sourceURL,
            attachmentID: attachmentID,
            originalFileName: originalFileName
        )
        do {
            try repository.addAttachment(
                AttachmentRecord(
                    id: attachmentID,
                    fileName: originalFileName,
                    role: role,
                    contentTypeIdentifier: file.contentTypeIdentifier,
                    byteCount: file.byteCount,
                    managedRelativePath: file.relativePath
                ),
                to: itemID
            )
        } catch {
            try? await attachmentFileStore.remove(relativePath: file.relativePath)
            throw error
        }
    }

    func openAttachment(_ attachmentID: UUID, for itemID: UUID) async throws {
        let path = try repository.attachmentPath(attachmentID, in: itemID)
        try await attachmentFileStore.open(relativePath: path)
    }

    private func validateDate(year: Int?, month: Int?, day: Int?) throws {
        if let year, !(1...9999).contains(year) {
            throw ItemDraftError.invalidYear
        }
        if let month, !(1...12).contains(month) {
            throw ItemDraftError.invalidMonth
        }
        if let day, !(1...31).contains(day) {
            throw ItemDraftError.invalidDay
        }

        guard let year, let month, let day else { return }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else {
            throw ItemDraftError.invalidDay
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else {
            throw ItemDraftError.invalidDay
        }
    }
}

private enum FolderNameError: LocalizedError {
    case empty

    var errorDescription: String? { "A folder name is required." }
}

private enum ItemDraftError: LocalizedError {
    case missingTitle
    case invalidYear
    case invalidMonth
    case invalidDay

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            "A title is required."
        case .invalidYear:
            "Enter a valid publication year."
        case .invalidMonth:
            "The publication month must be between 1 and 12."
        case .invalidDay:
            "The publication date is not valid."
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
