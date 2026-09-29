import SwiftUI

/// Paste a DOI and return the fetched draft to the shared item editor.
struct DoiLookupView: View {
    @Environment(LibraryViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    private let isReadOnly: Bool
    private let title: String
    private let onFound: ((ItemDraft) -> Void)?
    private let onMetadataFound: ((DOIMetadata) -> Void)?

    @State private var doiInput = ""
    @State private var isLookingUp = false
    @State private var errorMessage: String?

    init(onFound: @escaping (ItemDraft) -> Void) {
        self.isReadOnly = false
        self.title = "Add by DOI"
        self.onFound = onFound
        self.onMetadataFound = nil
        _doiInput = State(initialValue: "")
    }

    init(
        doi: String,
        onMetadataFound: @escaping (DOIMetadata) -> Void
    ) {
        self.isReadOnly = true
        self.title = "Update by DOI"
        self.onFound = nil
        self.onMetadataFound = onMetadataFound
        _doiInput = State(initialValue: doi)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("DOI") {
                        TextField("10.1234/example", text: $doiInput)
                            .disabled(isReadOnly)
                            .onSubmit { Task { await lookup() } }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    if isLookingUp {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Lookup") { Task { await lookup() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isLookingUp || doiInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(title)
        }
        .frame(width: 520, height: 280)
    }

    private func lookup() async {
        let raw = doiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isLookingUp = true
        errorMessage = nil
        defer { isLookingUp = false }

        if onMetadataFound != nil {
            switch await viewModel.lookupDOIMetadata(raw) {
            case let .success(metadata):
                onMetadataFound?(metadata)
                dismiss()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        } else {
            switch await viewModel.lookupDOI(raw) {
            case let .success(fetched):
                onFound?(fetched)
                dismiss()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
