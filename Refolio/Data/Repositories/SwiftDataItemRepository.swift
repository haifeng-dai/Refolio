import Foundation
import SwiftData

@MainActor
final class SwiftDataItemRepository: ItemRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [LibraryItem] {
        try modelContext.fetch(FetchDescriptor<Item>())
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(Self.libraryItem(from:))
    }

    func fetchFolders() throws -> [LibraryFolder] {
        try modelContext.fetch(FetchDescriptor<Folder>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { folder in
                LibraryFolder(
                    id: folder.id,
                    name: folder.name,
                    itemCount: folder.memberships.compactMap(\.item).filter { !$0.isTrashed }.count
                )
            }
    }

    func create(_ draft: ItemDraft, in folderID: UUID?) throws -> LibraryItem {
        let publication = try resolvePublication(for: draft)
        let authors = try resolveAuthors(named: draft.authorNames)
        let folder = try folderID.map(resolveFolder(id:))

        let item = Item(
            title: draft.title,
            abstract: draft.abstract,
            doi: draft.doi,
            publicationYear: draft.publicationYear,
            publicationMonth: draft.publicationMonth,
            publicationDay: draft.publicationDay,
            volume: draft.volume,
            issue: draft.issue,
            pageRange: draft.pageRange,
            urlString: draft.urlString,
            publication: publication
        )
        modelContext.insert(item)

        if let folder {
            modelContext.insert(FolderMembership(folder: folder, item: item))
        }

        for (position, author) in authors.enumerated() {
            let authorship = Authorship(position: position, item: item, author: author)
            modelContext.insert(authorship)
        }

        try modelContext.save()
        return Self.libraryItem(from: item)
    }

    func update(_ itemID: UUID, from draft: ItemDraft) throws {
        let item = try resolveItem(id: itemID)
        item.title = draft.title
        item.abstract = draft.abstract
        item.doi = draft.doi
        item.publicationYear = draft.publicationYear
        item.publicationMonth = draft.publicationMonth
        item.publicationDay = draft.publicationDay
        item.volume = draft.volume
        item.issue = draft.issue
        item.pageRange = draft.pageRange
        item.urlString = draft.urlString
        item.publication = try resolvePublication(for: draft)

        let existingAuthorNames = item.authorships
            .sorted { $0.position < $1.position }
            .compactMap { $0.author?.displayName }
        if existingAuthorNames != draft.authorNames {
            let oldAuthorships = item.authorships
            item.authorships = []
            for authorship in oldAuthorships {
                modelContext.delete(authorship)
            }

            let authors = try resolveAuthors(named: draft.authorNames)
            for (position, author) in authors.enumerated() {
                modelContext.insert(Authorship(position: position, item: item, author: author))
            }
        }

        item.updatedAt = .now
        try modelContext.save()
    }

    func createFolder(named name: String) throws -> LibraryFolder {
        let folders = try modelContext.fetch(FetchDescriptor<Folder>())
        if let existing = folders.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return LibraryFolder(
                id: existing.id,
                name: existing.name,
                itemCount: existing.memberships.compactMap(\.item).filter { !$0.isTrashed }.count
            )
        }

        let folder = Folder(name: name)
        modelContext.insert(folder)
        try modelContext.save()
        return LibraryFolder(id: folder.id, name: folder.name, itemCount: 0)
    }

    func add(_ itemID: UUID, to folderID: UUID) throws {
        let item = try resolveItem(id: itemID)
        let folder = try resolveFolder(id: folderID)
        guard !item.folderMemberships.contains(where: { $0.folder?.id == folderID }) else { return }
        modelContext.insert(FolderMembership(folder: folder, item: item))
        try modelContext.save()
    }

    func moveToTrash(_ itemID: UUID) throws {
        let item = try resolveItem(id: itemID)
        item.isTrashed = true
        item.updatedAt = .now
        try modelContext.save()
    }

    func restore(_ itemID: UUID) throws {
        let item = try resolveItem(id: itemID)
        item.isTrashed = false
        item.updatedAt = .now
        try modelContext.save()
    }

    func addAttachment(_ record: AttachmentRecord, to itemID: UUID) throws {
        let item = try resolveItem(id: itemID)
        let attachment = Attachment(
            id: record.id,
            fileName: record.fileName,
            roleRawValue: record.role.rawValue,
            contentTypeIdentifier: record.contentTypeIdentifier,
            byteCount: record.byteCount,
            managedRelativePath: record.managedRelativePath,
            item: item
        )
        modelContext.insert(attachment)
        do {
            try modelContext.save()
        } catch {
            item.attachments.removeAll { $0.id == attachment.id }
            modelContext.delete(attachment)
            throw error
        }
    }

    func attachmentFile(_ attachmentID: UUID, in itemID: UUID) throws -> AttachmentFileReference {
        let item = try resolveItem(id: itemID)
        guard let attachment = item.attachments.first(where: { $0.id == attachmentID }),
              let path = attachment.managedRelativePath else {
            throw LibraryRepositoryError.attachmentNotFound
        }
        return AttachmentFileReference(
            fileName: attachment.fileName,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            managedRelativePath: path,
            lastReadPosition: attachment.lastReadPageIndex.map {
                PDFReadingPosition(
                    pageIndex: $0,
                    pointX: attachment.lastReadPointX,
                    pointY: attachment.lastReadPointY,
                    zoom: attachment.lastReadZoom
                )
            }
        )
    }

    func saveReadingPosition(_ position: PDFReadingPosition, for attachmentID: UUID, in itemID: UUID) throws {
        let item = try resolveItem(id: itemID)
        guard let attachment = item.attachments.first(where: { $0.id == attachmentID }) else {
            throw LibraryRepositoryError.attachmentNotFound
        }
        guard attachment.lastReadPageIndex != position.pageIndex
                || attachment.lastReadPointX != position.pointX
                || attachment.lastReadPointY != position.pointY
                || attachment.lastReadZoom != position.zoom else { return }
        attachment.lastReadPageIndex = position.pageIndex
        attachment.lastReadPointX = position.pointX
        attachment.lastReadPointY = position.pointY
        attachment.lastReadZoom = position.zoom
        try modelContext.save()
    }

    func fetchNotes(for itemID: UUID) throws -> [LiteratureNote] {
        try resolveItem(id: itemID).notes
            .map { Self.libraryNote(from: $0, itemID: itemID) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createNote(_ draft: LiteratureNoteDraft, for itemID: UUID) throws -> LiteratureNote {
        let item = try resolveItem(id: itemID)
        let attachment: Attachment?
        if let attachmentID = draft.sourceAttachmentID {
            guard let source = item.attachments.first(where: { $0.id == attachmentID }) else {
                throw LibraryRepositoryError.attachmentNotFound
            }
            attachment = source
        } else {
            attachment = nil
        }

        let note = LiteratureNoteRecord(
            content: draft.content,
            sourcePageIndex: draft.sourcePageIndex,
            item: item,
            sourceAttachment: attachment
        )
        modelContext.insert(note)
        do {
            try modelContext.save()
        } catch {
            item.notes.removeAll { $0.id == note.id }
            modelContext.delete(note)
            throw error
        }
        return Self.libraryNote(from: note, itemID: itemID)
    }

    func updateNote(_ noteID: UUID, content: String, in itemID: UUID) throws -> LiteratureNote {
        let item = try resolveItem(id: itemID)
        guard let note = item.notes.first(where: { $0.id == noteID }) else {
            throw LibraryRepositoryError.noteNotFound
        }
        note.content = content
        note.updatedAt = .now
        try modelContext.save()
        return Self.libraryNote(from: note, itemID: itemID)
    }

    func deleteNote(_ noteID: UUID, in itemID: UUID) throws {
        let item = try resolveItem(id: itemID)
        guard let note = item.notes.first(where: { $0.id == noteID }) else {
            throw LibraryRepositoryError.noteNotFound
        }
        modelContext.delete(note)
        try modelContext.save()
    }

    private func resolvePublication(for draft: ItemDraft) throws -> Publication? {
        guard let title = draft.publicationTitle else { return nil }
        let literatureType = draft.literatureType ?? "Other"
        let publications = try modelContext.fetch(FetchDescriptor<Publication>())

        if let existing = publications.first(where: {
            $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && $0.literatureType == literatureType
        }) {
            return existing
        }

        let publication = Publication(title: title, literatureType: literatureType)
        modelContext.insert(publication)
        return publication
    }

    private func resolveFolder(id: UUID) throws -> Folder {
        guard let folder = try modelContext.fetch(FetchDescriptor<Folder>()).first(where: { $0.id == id }) else {
            throw LibraryRepositoryError.folderNotFound
        }
        return folder
    }

    private func resolveItem(id: UUID) throws -> Item {
        guard let item = try modelContext.fetch(FetchDescriptor<Item>()).first(where: { $0.id == id }) else {
            throw LibraryRepositoryError.itemNotFound
        }
        return item
    }

    private func resolveAuthors(named names: [String]) throws -> [Author] {
        var knownAuthors = try modelContext.fetch(FetchDescriptor<Author>())
        return names.map { name in
            if let existing = knownAuthors.first(where: {
                $0.displayName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return existing
            }

            let author = Author(literalName: name)
            modelContext.insert(author)
            knownAuthors.append(author)
            return author
        }
    }

    private static func libraryItem(from item: Item) -> LibraryItem {
        LibraryItem(
            id: item.id,
            title: item.title,
            abstract: item.abstract,
            doi: item.doi,
            publicationYear: item.publicationYear,
            publicationMonth: item.publicationMonth,
            publicationDay: item.publicationDay,
            volume: item.volume,
            issue: item.issue,
            pageRange: item.pageRange,
            urlString: item.urlString,
            authorNames: item.authorships
                .sorted { $0.position < $1.position }
                .compactMap { $0.author?.displayName },
            publicationTitle: item.publication?.title,
            literatureType: item.publication?.literatureType,
            folderIDs: item.folderMemberships.compactMap { $0.folder?.id },
            isTrashed: item.isTrashed,
            attachments: item.attachments.map {
                LibraryAttachment(
                    id: $0.id,
                    fileName: $0.fileName,
                    role: AttachmentRole(rawValue: $0.roleRawValue ?? "") ?? .other
                )
            }.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        )
    }

    private static func libraryNote(from note: LiteratureNoteRecord, itemID: UUID) -> LiteratureNote {
        LiteratureNote(
            id: note.id,
            itemID: itemID,
            content: note.content,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            sourceAttachmentName: note.sourceAttachment?.fileName,
            sourcePageIndex: note.sourcePageIndex
        )
    }
}

private enum LibraryRepositoryError: LocalizedError {
    case folderNotFound
    case itemNotFound
    case attachmentNotFound
    case noteNotFound

    var errorDescription: String? {
        switch self {
        case .folderNotFound: "The selected folder no longer exists."
        case .itemNotFound: "The selected item no longer exists."
        case .attachmentNotFound: "The attachment could not be found."
        case .noteNotFound: "The note could not be found."
        }
    }
}
