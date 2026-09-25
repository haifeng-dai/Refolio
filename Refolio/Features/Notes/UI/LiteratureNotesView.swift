import SwiftUI

struct LiteratureNotesView: View {
    @Environment(LibraryViewModel.self) private var viewModel

    let itemID: UUID
    var sourceAttachmentID: UUID? = nil
    var sourcePageIndex: Int? = nil

    @State private var isEditorPresented = false
    @State private var editingNote: LiteratureNote?
    @State private var draft = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: newNote) {
                    Label("New Note", systemImage: "plus")
                }
            }

            ForEach(viewModel.notes(for: itemID)) { note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(note.content)
                            .textSelection(.enabled)
                        Spacer(minLength: 4)
                        Menu {
                            Button("Edit Note", systemImage: "pencil") {
                                edit(note)
                            }
                            Button("Delete Note", systemImage: "trash", role: .destructive) {
                                errorMessage = viewModel.deleteNote(note.id, in: itemID)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                    }

                    if let source = sourceDescription(for: note) {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(note.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                Divider()
            }
        }
        .task(id: itemID) {
            errorMessage = viewModel.loadNotes(for: itemID)
        }
        .sheet(isPresented: $isEditorPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(editingNote == nil ? "New Note" : "Edit Note")
                    .font(.title2.weight(.semibold))

                TextEditor(text: $draft)
                    .font(.body)

                HStack {
                    Spacer()
                    Button("Cancel") { isEditorPresented = false }
                    Button("Save", action: saveNote)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 480, height: 320)
        }
        .alert(
            "Notes Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func newNote() {
        errorMessage = nil
        editingNote = nil
        draft = ""
        isEditorPresented = true
    }

    private func edit(_ note: LiteratureNote) {
        errorMessage = nil
        editingNote = note
        draft = note.content
        isEditorPresented = true
    }

    private func saveNote() {
        if let editingNote {
            errorMessage = viewModel.updateNote(editingNote.id, content: draft, in: itemID)
        } else {
            errorMessage = viewModel.createNote(
                LiteratureNoteDraft(
                    content: draft,
                    sourceAttachmentID: sourceAttachmentID,
                    sourcePageIndex: sourcePageIndex
                ),
                for: itemID
            )
        }
        if errorMessage == nil { isEditorPresented = false }
    }

    private func sourceDescription(for note: LiteratureNote) -> String? {
        guard let fileName = note.sourceAttachmentName else { return nil }
        if let pageIndex = note.sourcePageIndex {
            return "\(fileName) · Page \(pageIndex + 1)"
        }
        return fileName
    }
}
