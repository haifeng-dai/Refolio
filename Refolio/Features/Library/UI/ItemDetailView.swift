import SwiftUI

struct ItemDetailView: View {
    let item: LibraryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)

                if !item.authorNames.isEmpty {
                    Text(item.authorNames.joined(separator: ", "))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let publicationTitle = item.publicationTitle {
                    LabeledContent("Publication", value: publicationTitle)
                }
                if let literatureType = item.literatureType {
                    LabeledContent("Type", value: literatureType)
                }
                if let date = publicationDate {
                    LabeledContent("Publication date", value: date)
                }
                if let doi = item.doi {
                    LabeledContent("DOI", value: doi)
                        .textSelection(.enabled)
                }
                if let pages = item.pageRange {
                    LabeledContent("Pages", value: pages)
                }
                if let abstract = item.abstract {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Abstract")
                            .font(.headline)
                        Text(abstract)
                            .textSelection(.enabled)
                    }
                }
                if let urlString = item.urlString, let url = URL(string: urlString) {
                    Link(urlString, destination: url)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
        }
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
