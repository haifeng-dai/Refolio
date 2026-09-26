import SwiftUI

struct MainWorkspaceView: View {
    @Environment(LibraryViewModel.self) private var viewModel

    var body: some View {
        Group {
            switch viewModel.workspaceMode {
            case .library:
                LibraryView()
            case .reader:
                if let request = viewModel.activeReaderRequest {
                    PDFReaderView(request: request)
                        .id(request)
                } else {
                    ReaderEmptyStateView()
                }
            }
        }
    }
}

struct ReaderEmptyStateView: View {
    @Environment(LibraryViewModel.self) private var viewModel

    var body: some View {
        ContentUnavailableView {
            Label("No Document Open", systemImage: "doc.richtext")
        } description: {
            Text("Double-click a literature in your library or choose a file to start reading.")
        } actions: {
            Button("Back to Library", systemImage: "books.vertical") {
                viewModel.workspaceMode = .library
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Library", systemImage: "books.vertical") {
                    viewModel.workspaceMode = .library
                }
                .labelStyle(.iconOnly)
                .help("Back to Library")
            }
        }
    }
}
