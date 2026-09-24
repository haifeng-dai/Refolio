import Foundation
import SwiftData

@MainActor
enum DebugSampleData {
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        guard try modelContext.fetch(FetchDescriptor<Item>()).isEmpty else { return }

        let folder = Folder(name: "Sample Reading List")
        modelContext.insert(folder)

        let samples: [(title: String, author: String, publication: String, year: Int)] = [
            (
                "Sample Item: Building a Reproducible Research Workflow",
                "Alex Example",
                "Journal of Sample Research",
                2024
            ),
            (
                "Sample Item: Metadata Quality in Digital Libraries",
                "Jordan Sample",
                "Proceedings of Example Studies",
                2023
            ),
            (
                "Sample Item: Designing an Efficient PDF Reading Interface",
                "Taylor Test",
                "Sample Computing Review",
                2022
            )
        ]

        for (index, sample) in samples.enumerated() {
            let publication = Publication(title: sample.publication, literatureType: "Journal article")
            let author = Author(literalName: sample.author)
            let item = Item(
                title: sample.title,
                abstract: "Placeholder metadata for testing the Refolio library interface.",
                publicationYear: sample.year,
                publicationMonth: 6,
                publicationDay: 15,
                publication: publication
            )

            modelContext.insert(publication)
            modelContext.insert(author)
            modelContext.insert(item)
            modelContext.insert(Authorship(position: 0, item: item, author: author))

            if index < 2 {
                modelContext.insert(FolderMembership(folder: folder, item: item))
            }
        }

        try modelContext.save()
    }
}
