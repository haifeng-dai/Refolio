import SwiftUI
import SwiftData

@MainActor
@main
struct RefolioApp: App {
    private let modelContainer: ModelContainer
    @State private var libraryViewModel: LibraryViewModel

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Item.self,
                Publication.self,
                Author.self,
                Authorship.self,
                Attachment.self,
                Folder.self,
                FolderMembership.self
            )
        } catch {
            fatalError("Could not create the Refolio library: \(error)")
        }
        modelContainer = container

        #if DEBUG
        do {
            try DebugSampleData.seedIfNeeded(in: container.mainContext)
        } catch {
            fatalError("Could not create Refolio sample data: \(error)")
        }
        #endif

        let repository = SwiftDataItemRepository(modelContext: container.mainContext)
        let attachmentFileStore = LocalAttachmentFileStore()
        let workflow = ItemLibraryWorkflow(repository: repository, attachmentFileStore: attachmentFileStore)
        _libraryViewModel = State(initialValue: LibraryViewModel(workflow: workflow))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(libraryViewModel)
        }
        .modelContainer(modelContainer)
    }
}
