import SwiftUI

struct NewFolderView: View {
    let onCreate: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    TextField("Folder name", text: $name)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                .formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Create") { create() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("New Folder")
        }
        .frame(width: 400, height: 180)
    }

    private func create() {
        if let error = onCreate(name) {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}
