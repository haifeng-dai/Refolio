import SwiftUI

struct DOIUpdateComparisonView: View {
    let preview: DOIUpdatePreview
    let onApply: (DOIUpdatePlan) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var choices: [DOIUpdateField: DOIUpdateChoice]
    @State private var errorMessage: String?

    init(
        preview: DOIUpdatePreview,
        onApply: @escaping (DOIUpdatePlan) -> String?
    ) {
        self.preview = preview
        self.onApply = onApply
        _choices = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: preview.changedFields.map { ($0, DOIUpdateChoice.keepLocal) }
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    LabeledContent("Title", value: preview.local.title)
                    LabeledContent("DOI", value: preview.remote.doi)
                }

                if preview.changedFields.isEmpty {
                    Section {
                        Text("The local metadata is already identical to the DOI record.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(DOIUpdateField.allCases) { field in
                    fieldSection(field)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Update by DOI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(preview.changedFields.isEmpty)
                }
            }
        }
        .frame(width: 700, height: 720)
        .alert("Could Not Update Item", isPresented: errorIsPresented) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func fieldSection(_ field: DOIUpdateField) -> some View {
        let remoteAvailable = isRemoteValueAvailable(for: field)
        let changed = preview.changedFields.contains(field)

        Section(field.title) {
            LabeledContent("Local") {
                Text(localValue(for: field))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            LabeledContent("DOI") {
                Text(remoteValue(for: field))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if changed {
                Picker("Use", selection: choiceBinding(for: field)) {
                    Text("Keep Local").tag(DOIUpdateChoice.keepLocal)
                    Text("Use DOI").tag(DOIUpdateChoice.useRemote)
                }
                .pickerStyle(.segmented)
            } else if !remoteAvailable {
                Text("DOI did not provide this field. The local value will be kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Same")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func choiceBinding(for field: DOIUpdateField) -> Binding<DOIUpdateChoice> {
        Binding(
            get: { choices[field] ?? .keepLocal },
            set: { choices[field] = $0 }
        )
    }

    private func save() {
        let selectedFields = Set(
            preview.changedFields.filter { choices[$0] == .useRemote }
        )
        guard !selectedFields.isEmpty else {
            dismiss()
            return
        }

        let plan = DOIUpdatePlan(
            itemID: preview.itemID,
            local: preview.local,
            remote: preview.remote,
            selectedFields: selectedFields
        )
        if let error = onApply(plan) {
            errorMessage = error
        } else {
            dismiss()
        }
    }

    private func isRemoteValueAvailable(for field: DOIUpdateField) -> Bool {
        switch field {
        case .title: preview.remote.title != nil
        case .abstract: preview.remote.abstract != nil
        case .publicationDate:
            preview.remote.publicationYear != nil
                || preview.remote.publicationMonth != nil
                || preview.remote.publicationDay != nil
        case .volume: preview.remote.volume != nil
        case .issue: preview.remote.issue != nil
        case .pageRange: preview.remote.pageRange != nil
        case .url: preview.remote.urlString != nil
        case .authors: preview.remote.authors != nil
        case .publication:
            preview.remote.publicationTitle != nil || preview.remote.literatureType != nil
        }
    }

    private func localValue(for field: DOIUpdateField) -> String {
        switch field {
        case .title: preview.local.title
        case .abstract: preview.local.abstract ?? "—"
        case .publicationDate:
            dateString(
                year: preview.local.publicationYear,
                month: preview.local.publicationMonth,
                day: preview.local.publicationDay
            )
        case .volume: preview.local.volume ?? "—"
        case .issue: preview.local.issue ?? "—"
        case .pageRange: preview.local.pageRange ?? "—"
        case .url: preview.local.urlString ?? "—"
        case .authors: orderedAuthors(preview.local.authors)
        case .publication:
            publicationString(title: preview.local.publicationTitle, type: preview.local.literatureType)
        }
    }

    private func remoteValue(for field: DOIUpdateField) -> String {
        switch field {
        case .title: return preview.remote.title ?? "Not provided"
        case .abstract: return preview.remote.abstract ?? "Not provided"
        case .publicationDate:
            return dateString(
                year: preview.remote.publicationYear,
                month: preview.remote.publicationMonth,
                day: preview.remote.publicationDay
            )
        case .volume: return preview.remote.volume ?? "Not provided"
        case .issue: return preview.remote.issue ?? "Not provided"
        case .pageRange: return preview.remote.pageRange ?? "Not provided"
        case .url: return preview.remote.urlString ?? "Not provided"
        case .authors:
            guard let authors = preview.remote.authors else { return "Not provided" }
            return orderedAuthors(authors.map {
                AuthorDraft(
                    givenName: $0.givenName,
                    familyName: $0.familyName,
                    literalName: $0.literalName,
                    orcid: $0.orcid
                )
            })
        case .publication:
            return publicationString(title: preview.remote.publicationTitle, type: preview.remote.literatureType)
        }
    }

    private func dateString(year: Int?, month: Int?, day: Int?) -> String {
        guard year != nil || month != nil || day != nil else { return "—" }
        return [year.map(String.init), month.map(String.init), day.map(String.init)]
            .compactMap { $0 }
            .joined(separator: "-")
    }

    private func publicationString(title: String?, type: String?) -> String {
        [title, type]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .ifEmpty("—")
    }

    private func orderedAuthors(_ authors: [AuthorDraft]) -> String {
        guard !authors.isEmpty else { return "—" }
        return authors.enumerated()
            .map { "\($0.offset + 1). \(AuthorNameFormatter.inline($0.element))" }
            .joined(separator: "\n")
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 { errorMessage = nil }
            }
        )
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private extension DOIUpdateField {
    var title: String {
        switch self {
        case .title: "Title"
        case .abstract: "Abstract"
        case .publicationDate: "Publication Date"
        case .volume: "Volume"
        case .issue: "Issue"
        case .pageRange: "Pages"
        case .url: "URL"
        case .authors: "Authors"
        case .publication: "Publication"
        }
    }
}
