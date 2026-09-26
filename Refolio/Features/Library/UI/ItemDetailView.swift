import SwiftUI

struct ItemDetailView: View {
    let item: LibraryItem
    var onOpenAttachment: ((LibraryAttachment) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                Divider()

                if !item.attachments.isEmpty {
                    attachmentsSection
                }

                if let abstract = item.abstract, !abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abstract")
                            .font(.headline)
                        Text(abstract)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }

                LiteratureNotesView(itemID: item.id)

                if let urlString = item.urlString, let url = URL(string: urlString) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(urlString, destination: url)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName(for: item.literatureType))
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(3)
                    .textSelection(.enabled)

                if !item.authorNames.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Authors:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(item.authorNames.joined(separator: ", "))
                            .font(.subheadline.weight(.medium))
                            .textSelection(.enabled)
                    }
                }

                if let pub = item.publicationTitle, !pub.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Source:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(pub)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let doi = item.doi, !doi.isEmpty {
                    HStack(spacing: 4) {
                        Text("DOI:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(doi)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Spacer()

            if let date = publicationDate {
                Text(date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.headline)

            ForEach(item.attachments) { attachment in
                HStack(spacing: 10) {
                    Image(systemName: attachment.role == .main ? "doc.richtext.fill" : "paperclip")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.fileName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(attachment.role.menuTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let onOpenAttachment {
                        Button("Open") {
                            onOpenAttachment(attachment)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func iconName(for type: String?) -> String {
        guard let type = type?.lowercased() else { return "doc.text" }
        if type.contains("book") { return "book" }
        if type.contains("journal") || type.contains("article") { return "newspaper" }
        if type.contains("conference") || type.contains("proceedings") { return "person.3" }
        return "doc.text"
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
