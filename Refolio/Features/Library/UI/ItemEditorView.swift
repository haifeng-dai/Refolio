import SwiftUI

struct ItemEditorView: View {
    let item: LibraryItem?
    let onSave: (ItemDraft) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var doi = ""
    @State private var authorLines = ""
    @State private var publicationTitle = ""
    @State private var literatureType = Self.literatureTypes[0]
    @State private var year = ""
    @State private var month = ""
    @State private var day = ""
    @State private var abstract = ""
    @State private var volume = ""
    @State private var issue = ""
    @State private var pageRange = ""
    @State private var url = ""
    @State private var errorMessage: String?

    private static let literatureTypes = [
        "Journal article",
        "Conference paper",
        "Book",
        "Book chapter",
        "Preprint",
        "Thesis",
        "Report",
        "Dataset",
        "Other"
    ]

    init(
        item: LibraryItem? = nil,
        initialDraft: ItemDraft? = nil,
        onSave: @escaping (ItemDraft) -> String?
    ) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? initialDraft?.title ?? "")
        _doi = State(initialValue: item?.doi ?? initialDraft?.doi ?? "")
        _authorLines = State(initialValue: item?.authorNames.joined(separator: "\n") ?? initialDraft?.authorNames.joined(separator: "\n") ?? "")
        _publicationTitle = State(initialValue: item?.publicationTitle ?? initialDraft?.publicationTitle ?? "")
        _literatureType = State(initialValue: item?.literatureType ?? initialDraft?.literatureType ?? Self.literatureTypes[0])
        _year = State(initialValue: item?.publicationYear.map(String.init) ?? initialDraft?.publicationYear.map(String.init) ?? "")
        _month = State(initialValue: item?.publicationMonth.map(String.init) ?? initialDraft?.publicationMonth.map(String.init) ?? "")
        _day = State(initialValue: item?.publicationDay.map(String.init) ?? initialDraft?.publicationDay.map(String.init) ?? "")
        _abstract = State(initialValue: item?.abstract ?? initialDraft?.abstract ?? "")
        _volume = State(initialValue: item?.volume ?? initialDraft?.volume ?? "")
        _issue = State(initialValue: item?.issue ?? initialDraft?.issue ?? "")
        _pageRange = State(initialValue: item?.pageRange ?? initialDraft?.pageRange ?? "")
        _url = State(initialValue: item?.urlString ?? initialDraft?.urlString ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                Section("Item") {
                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("DOI", text: $doi)
                    HStack {
                        TextField("Year", text: $year)
                        TextField("Month", text: $month)
                        TextField("Day", text: $day)
                    }
                    TextField("Publication / journal", text: $publicationTitle)
                    if !publicationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Picker("Literature type", selection: $literatureType) {
                            ForEach(Self.literatureTypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                    }
                }

                Section("Authors") {
                    Text("Enter one author per line; the order is preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $authorLines)
                        .frame(minHeight: 80, maxHeight: 130)
                }

                Section("More details") {
                    TextField("Volume", text: $volume)
                    TextField("Issue", text: $issue)
                    TextField("Pages", text: $pageRange)
                    TextField("URL", text: $url)
                    TextEditor(text: $abstract)
                        .frame(minHeight: 80, maxHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if abstract.isEmpty {
                                Text("Abstract")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                }
                .formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
        }
        .frame(width: 620, height: 720)
        .alert("Could Not Save Item", isPresented: errorIsPresented) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func save() {
        do {
            let draft = ItemDraft(
                title: title,
                abstract: optionalText(abstract),
                doi: optionalText(doi),
                publicationYear: try optionalInteger(year, field: "Year"),
                publicationMonth: try optionalInteger(month, field: "Month"),
                publicationDay: try optionalInteger(day, field: "Day"),
                volume: optionalText(volume),
                issue: optionalText(issue),
                pageRange: optionalText(pageRange),
                urlString: optionalText(url),
                authorNames: authorLines
                    .components(separatedBy: .newlines)
                    .compactMap(optionalText),
                publicationTitle: optionalText(publicationTitle),
                literatureType: optionalText(publicationTitle) == nil ? nil : literatureType
            )

            if let error = onSave(draft) {
                errorMessage = error
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optionalInteger(_ value: String, field: String) throws -> Int? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let integer = Int(value) else {
            throw InputError.invalidNumber(field)
        }
        return integer
    }

    private func optionalText(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )
    }
}

private enum InputError: LocalizedError {
    case invalidNumber(String)

    var errorDescription: String? {
        if case let .invalidNumber(field) = self {
            return "Enter a number for \(field.lowercased())."
        }
        return nil
    }
}
