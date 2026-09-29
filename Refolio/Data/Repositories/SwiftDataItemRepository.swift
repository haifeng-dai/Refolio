import Foundation
import SwiftData

@MainActor
final class SwiftDataItemRepository: ItemRepository {
    private let modelContext: ModelContext

    private struct ResolvedAuthor {
        let author: Author
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [LibraryItem] {
        try modelContext.fetch(FetchDescriptor<Item>())
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(Self.libraryItem(from:))
    }

    func findNonTrashed(doi: String) throws -> [LibraryItem] {
        let normalized = DOIString.normalize(doi) ?? doi
        return try modelContext.fetch(FetchDescriptor<Item>())
            .filter { !$0.isTrashed }
            .filter { item in
                guard let itemDOI = item.doi else { return false }
                return DOIString.normalize(itemDOI) == normalized
            }
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
        let authors = try resolveAuthors(for: draft.authors)
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

        for (position, resolved) in authors.enumerated() {
            let authorship = Authorship(position: position, item: item, author: resolved.author)
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

        let existingAuthors = item.authorships
            .sorted { $0.position < $1.position }
            .compactMap { authorship -> AuthorDraft? in
                guard let author = authorship.author else { return nil }
                return AuthorDraft(
                    givenName: author.givenName,
                    familyName: author.familyName,
                    literalName: author.literalName,
                    orcid: author.orcid
                )
            }
        if existingAuthors != draft.authors {
            try mergeAuthorships(of: item, with: draft.authors)
        }

        item.updatedAt = .now
        try modelContext.save()
    }

    private func mergeAuthorships(of item: Item, with drafts: [AuthorDraft]) throws {
        let existingAuthorships = item.authorships.sorted { $0.position < $1.position }
        let authors = try resolveAuthors(for: drafts)
        var existingByAuthorID: [UUID: [Authorship]] = [:]
        for authorship in existingAuthorships {
            guard let authorID = authorship.author?.id else { continue }
            existingByAuthorID[authorID, default: []].append(authorship)
        }

        var usedAuthorshipIDs = Set<UUID>()
        var mergedAuthorships: [Authorship] = []
        mergedAuthorships.reserveCapacity(authors.count)

        for (position, resolved) in authors.enumerated() {
            let existing = existingByAuthorID[resolved.author.id]?.first {
                !usedAuthorshipIDs.contains($0.id)
            }
            if let existing {
                usedAuthorshipIDs.insert(existing.id)
                if existing.position != position {
                    existing.position = position
                }
                mergedAuthorships.append(existing)
            } else {
                let authorship = Authorship(position: position, item: item, author: resolved.author)
                modelContext.insert(authorship)
                mergedAuthorships.append(authorship)
            }
        }

        for authorship in existingAuthorships where !usedAuthorshipIDs.contains(authorship.id) {
            modelContext.delete(authorship)
        }

        let existingIDs = Set(existingAuthorships.map(\.id))
        let mergedIDs = Set(mergedAuthorships.map(\.id))
        if existingIDs != mergedIDs {
            item.authorships = mergedAuthorships
        }
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

    func add(_ itemIDs: Set<UUID>, to folderID: UUID) throws {
        guard !itemIDs.isEmpty else { return }

        let folder = try resolveFolder(id: folderID)
        let items = try itemIDs.map { try resolveItem(id: $0) }
        let membershipsToAdd = items
            .filter { item in
                !item.folderMemberships.contains(where: { $0.folder?.id == folderID })
            }
            .map { FolderMembership(folder: folder, item: $0) }

        guard !membershipsToAdd.isEmpty else { return }

        do {
            try modelContext.transaction {
                for membership in membershipsToAdd {
                    modelContext.insert(membership)
                }
            }
        } catch {
            for membership in membershipsToAdd {
                membership.item?.folderMemberships.removeAll { $0.id == membership.id }
                membership.folder?.memberships.removeAll { $0.id == membership.id }
                modelContext.delete(membership)
            }
            throw error
        }
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

    func fetchTextHighlights(for attachmentID: UUID, in itemID: UUID) throws -> [TextHighlight] {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        return try attachment.textHighlights
            .sorted { $0.createdAt < $1.createdAt }
            .map(Self.textHighlight(from:))
    }

    func createTextHighlight(
        _ draft: TextHighlightDraft,
        for attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        let record = TextHighlightRecord(
            selectedText: draft.selectedText,
            color: draft.color,
            geometryData: try JSONEncoder().encode(draft.pages),
            attachment: attachment
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            attachment.textHighlights.removeAll { $0.id == record.id }
            modelContext.delete(record)
            throw error
        }
        return TextHighlight(
            id: record.id,
            selectedText: record.selectedText,
            createdAt: record.createdAt,
            color: record.color,
            pages: draft.pages
        )
    }

    func updateTextHighlightGeometry(
        _ pages: [TextHighlightPage],
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.textHighlights.first(where: { $0.id == highlightID }) else {
            throw LibraryRepositoryError.textHighlightNotFound
        }

        let previousGeometry = record.geometryData
        record.geometryData = try JSONEncoder().encode(pages)
        do {
            try modelContext.save()
        } catch {
            record.geometryData = previousGeometry
            throw error
        }

        return TextHighlight(
            id: record.id,
            selectedText: record.selectedText,
            createdAt: record.createdAt,
            color: record.color,
            pages: pages
        )
    }

    func deleteTextHighlight(_ highlightID: UUID, attachmentID: UUID, in itemID: UUID) throws {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.textHighlights.first(where: { $0.id == highlightID }) else {
            throw LibraryRepositoryError.textHighlightNotFound
        }
        deleteAnnotationComments(for: highlightID, from: attachment)
        modelContext.delete(record)
        try modelContext.save()
    }

    func updateTextHighlightColor(
        _ color: TextHighlightColor,
        for highlightID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> TextHighlight {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.textHighlights.first(where: { $0.id == highlightID }) else {
            throw LibraryRepositoryError.textHighlightNotFound
        }
        let previousColor = record.color
        record.colorRed = color.red
        record.colorGreen = color.green
        record.colorBlue = color.blue
        record.colorAlpha = color.alpha
        do {
            try modelContext.save()
        } catch {
            record.colorRed = previousColor.red
            record.colorGreen = previousColor.green
            record.colorBlue = previousColor.blue
            record.colorAlpha = previousColor.alpha
            throw error
        }
        return try Self.textHighlight(from: record)
    }

    func fetchRectangleMarks(for attachmentID: UUID, in itemID: UUID) throws -> [RectangleMark] {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        return attachment.rectangleMarks
            .sorted { $0.createdAt < $1.createdAt }
            .map(Self.rectangleMark(from:))
    }

    func createRectangleMark(
        _ draft: RectangleMarkDraft,
        for attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        let record = RectangleMarkRecord(
            pageIndex: draft.pageIndex,
            x: draft.x,
            y: draft.y,
            width: draft.width,
            height: draft.height,
            color: draft.color,
            attachment: attachment
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            attachment.rectangleMarks.removeAll { $0.id == record.id }
            modelContext.delete(record)
            throw error
        }
        return Self.rectangleMark(from: record)
    }

    func deleteRectangleMark(_ markID: UUID, attachmentID: UUID, in itemID: UUID) throws {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.rectangleMarks.first(where: { $0.id == markID }) else {
            throw LibraryRepositoryError.rectangleMarkNotFound
        }
        deleteAnnotationComments(for: markID, from: attachment)
        modelContext.delete(record)
        try modelContext.save()
    }

    func updateRectangleMarkColor(
        _ color: TextHighlightColor,
        for markID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> RectangleMark {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.rectangleMarks.first(where: { $0.id == markID }) else {
            throw LibraryRepositoryError.rectangleMarkNotFound
        }
        let previousColor = record.color
        record.colorRed = color.red
        record.colorGreen = color.green
        record.colorBlue = color.blue
        record.colorAlpha = color.alpha
        do {
            try modelContext.save()
        } catch {
            record.colorRed = previousColor.red
            record.colorGreen = previousColor.green
            record.colorBlue = previousColor.blue
            record.colorAlpha = previousColor.alpha
            throw error
        }
        return Self.rectangleMark(from: record)
    }

    func fetchAnnotationComments(for attachmentID: UUID, in itemID: UUID) throws -> [AnnotationComment] {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        return attachment.annotationComments
            .sorted { $0.updatedAt < $1.updatedAt }
            .map(Self.annotationComment(from:))
    }

    func createAnnotationComment(
        _ draft: AnnotationCommentDraft,
        for annotationID: UUID,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> AnnotationComment {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard attachment.textHighlights.contains(where: { $0.id == annotationID })
                || attachment.rectangleMarks.contains(where: { $0.id == annotationID }) else {
            throw LibraryRepositoryError.annotationNotFound
        }
        let record = AnnotationCommentRecord(
            annotationID: annotationID,
            content: draft.content,
            attachment: attachment
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            attachment.annotationComments.removeAll { $0.id == record.id }
            modelContext.delete(record)
            throw error
        }
        return Self.annotationComment(from: record)
    }

    func updateAnnotationComment(
        _ commentID: UUID,
        content: String,
        attachmentID: UUID,
        in itemID: UUID
    ) throws -> AnnotationComment {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.annotationComments.first(where: { $0.id == commentID }) else {
            throw LibraryRepositoryError.annotationCommentNotFound
        }
        let previousContent = record.content
        let previousUpdatedAt = record.updatedAt
        record.content = content
        record.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            record.content = previousContent
            record.updatedAt = previousUpdatedAt
            throw error
        }
        return Self.annotationComment(from: record)
    }

    func deleteAnnotationComment(_ commentID: UUID, attachmentID: UUID, in itemID: UUID) throws {
        let attachment = try resolveAttachment(attachmentID, in: itemID)
        guard let record = attachment.annotationComments.first(where: { $0.id == commentID }) else {
            throw LibraryRepositoryError.annotationCommentNotFound
        }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func deleteAnnotationComments(for annotationID: UUID, from attachment: Attachment) {
        for comment in attachment.annotationComments where comment.annotationID == annotationID {
            modelContext.delete(comment)
        }
    }

    private func resolveAttachment(_ attachmentID: UUID, in itemID: UUID) throws -> Attachment {
        let item = try resolveItem(id: itemID)
        guard let attachment = item.attachments.first(where: { $0.id == attachmentID }) else {
            throw LibraryRepositoryError.attachmentNotFound
        }
        return attachment
    }

    private static func textHighlight(from record: TextHighlightRecord) throws -> TextHighlight {
        let pages: [TextHighlightPage]
        do {
            pages = try JSONDecoder().decode([TextHighlightPage].self, from: record.geometryData)
        } catch {
            throw LibraryRepositoryError.invalidHighlightGeometry
        }
        return TextHighlight(
            id: record.id,
            selectedText: record.selectedText,
            createdAt: record.createdAt,
            color: record.color,
            pages: pages
        )
    }

    private static func rectangleMark(from record: RectangleMarkRecord) -> RectangleMark {
        RectangleMark(
            id: record.id,
            pageIndex: record.pageIndex,
            x: record.x,
            y: record.y,
            width: record.width,
            height: record.height,
            createdAt: record.createdAt,
            color: record.color
        )
    }

    private static func annotationComment(from record: AnnotationCommentRecord) -> AnnotationComment {
        AnnotationComment(
            id: record.id,
            annotationID: record.annotationID,
            content: record.content,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func resolvePublication(for draft: ItemDraft) throws -> Publication? {
        try resolvePublication(title: draft.publicationTitle, literatureType: draft.literatureType)
    }

    private func resolvePublication(title: String?, literatureType: String?) throws -> Publication? {
        guard let title = title?.trimmedOrNil else { return nil }
        let literatureType = literatureType?.trimmedOrNil ?? "Other"
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

    private func resolveAuthors(for drafts: [AuthorDraft]) throws -> [ResolvedAuthor] {
        var knownAuthors = try modelContext.fetch(FetchDescriptor<Author>())
        return drafts.compactMap { draft in
            guard let draft = draft.normalized() else { return nil }

            if let existing = knownAuthors.first(where: {
                sameRepresentation($0, draft) && compatibleORCID($0.orcid, draft.orcid)
            }) {
                return ResolvedAuthor(author: existing)
            }

            let author = Author(
                givenName: draft.givenName,
                familyName: draft.familyName,
                literalName: draft.literalName,
                orcid: draft.orcid
            )
            modelContext.insert(author)
            knownAuthors.append(author)
            return ResolvedAuthor(author: author)
        }
    }

    private func sameRepresentation(_ author: Author, _ draft: AuthorDraft) -> Bool {
        normalized(author.givenName) == normalized(draft.givenName)
            && normalized(author.familyName) == normalized(draft.familyName)
            && normalized(author.literalName) == normalized(draft.literalName)
    }

    private func compatibleORCID(_ existing: String?, _ incoming: String?) -> Bool {
        switch (existing.flatMap(ORCIDString.normalize), incoming.flatMap(ORCIDString.normalize)) {
        case (nil, nil):
            true
        case let (existing?, incoming?):
            existing.caseInsensitiveCompare(incoming) == .orderedSame
        default:
            false
        }
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
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
            }.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending },
            authors: item.authorships
                .sorted { $0.position < $1.position }
                .compactMap { authorship in
                    guard let author = authorship.author else { return nil }
                    return AuthorDraft(
                        givenName: author.givenName,
                        familyName: author.familyName,
                        literalName: author.literalName,
                        orcid: author.orcid
                    )
                }
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
    case textHighlightNotFound
    case rectangleMarkNotFound
    case annotationNotFound
    case annotationCommentNotFound
    case invalidHighlightGeometry

    var errorDescription: String? {
        switch self {
        case .folderNotFound: "The selected folder no longer exists."
        case .itemNotFound: "The selected item no longer exists."
        case .attachmentNotFound: "The attachment could not be found."
        case .noteNotFound: "The note could not be found."
        case .textHighlightNotFound: "The highlight could not be found."
        case .rectangleMarkNotFound: "The rectangle annotation could not be found."
        case .annotationNotFound: "The selected annotation could not be found."
        case .annotationCommentNotFound: "The annotation comment could not be found."
        case .invalidHighlightGeometry: "The saved highlight geometry could not be read."
        }
    }
}
