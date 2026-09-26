import SwiftUI

/// Paste a DOI and return the fetched draft to the shared item editor.
struct DoiLookupView: View {
    @Environment(LibraryViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    let onFound: (ItemDraft) -> Void

    @State private var doiInput = ""
    @State private var isLookingUp = false
    @State private var errorMessage: String?

    init(onFound: @escaping (ItemDraft) -> Void) {
        self.onFound = onFound
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("DOI") {
                        TextField("10.1234/example", text: $doiInput)
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
            .navigationTitle("Add by DOI")
        }
        .frame(width: 520, height: 280)
    }

    private func lookup() async {
        let raw = doiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isLookingUp = true
        errorMessage = nil
        defer { isLookingUp = false }

        switch await viewModel.lookupDOI(raw) {
        case let .success(fetched):
            onFound(fetched)
            dismiss()
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }
}
