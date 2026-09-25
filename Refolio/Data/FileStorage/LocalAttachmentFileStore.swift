import CryptoKit
import Foundation
import AppKit
import UniformTypeIdentifiers

actor LocalAttachmentFileStore: AttachmentFileStore {
    private let fileManager = FileManager.default

    func copy(from sourceURL: URL, attachmentID: UUID, originalFileName: String) async throws -> ManagedAttachmentFile {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard try sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw AttachmentFileError.directoryNotAllowed
        }

        let fileAttributes = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let relativeDirectory = "Attachments/\(attachmentID.uuidString)"
        let relativePath = "\(relativeDirectory)/\(Self.storedFileName(attachmentID: attachmentID, originalFileName: originalFileName))"
        let directoryURL = try appSupportURL().appending(path: relativeDirectory, directoryHint: .isDirectory)
        let destinationURL = try fileURL(for: relativePath)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }

        return ManagedAttachmentFile(
            relativePath: relativePath,
            contentTypeIdentifier: UTType(filenameExtension: destinationURL.pathExtension)?.identifier,
            byteCount: fileAttributes.fileSize.map(Int64.init)
        )
    }

    func remove(relativePath: String) async throws {
        let url = try fileURL(for: relativePath)
        try fileManager.removeItem(at: url)
        try fileManager.removeItem(at: url.deletingLastPathComponent())
    }

    func open(relativePath: String) async throws {
        let url = try fileURL(for: relativePath)
        try await MainActor.run {
            guard NSWorkspace.shared.open(url) else {
                throw AttachmentFileError.couldNotOpen
            }
        }
    }

    func url(for relativePath: String) async throws -> URL {
        try fileURL(for: relativePath)
    }

    nonisolated static func storedFileName(attachmentID: UUID, originalFileName: String) -> String {
        let digest = SHA256.hash(data: Data(attachmentID.uuidString.utf8))
        let prefix = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        let fileExtension = URL(fileURLWithPath: originalFileName).pathExtension
        return fileExtension.isEmpty ? prefix : "\(prefix).\(fileExtension)"
    }

    private func fileURL(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/")
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw AttachmentFileError.invalidPath
        }
        return try appSupportURL().appending(path: relativePath)
    }

    private func appSupportURL() throws -> URL {
        guard let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AttachmentFileError.applicationSupportUnavailable
        }
        return url.appending(path: "Refolio", directoryHint: .isDirectory)
    }
}

private enum AttachmentFileError: LocalizedError {
    case applicationSupportUnavailable
    case directoryNotAllowed
    case invalidPath
    case couldNotOpen

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "The application support folder is unavailable."
        case .directoryNotAllowed:
            "Choose a file, not a folder."
        case .invalidPath:
            "The attachment path is invalid."
        case .couldNotOpen:
            "The file could not be opened."
        }
    }
}
