import SwiftUI

struct ItemDetailView: View {
    let item: LibraryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                if !item.authorNames.isEmpty {
                    Text(item.authorNames.joined(separator: ", "))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                metadata

                if let abstract = item.abstract {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Abstract")
                            .font(.headline)
                        Text(abstract)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                LiteratureNotesView(itemID: item.id)

                if let urlString = item.urlString, let url = URL(string: urlString) {
                    Link(urlString, destination: url)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let publicationTitle = item.publicationTitle {
                detailRow("Publication", publicationTitle)
            }
            if let literatureType = item.literatureType {
                detailRow("Type", literatureType)
            }
            if let date = publicationDate {
                detailRow("Publication date", date)
            }
            if let doi = item.doi {
                detailRow("DOI", doi)
            }
            if let pages = item.pageRange {
                detailRow("Pages", pages)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publicationDate: String? {
        let parts = [
            item.publicationYear.map(String.init),
            item.publicationMonth.map { String(format: "%02d", $0) },
            item.publicationDay.map { String(format: "%02d", $0) }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "-")
    }
}
