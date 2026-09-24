import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  private let sidebarMinimumWidth: CGFloat = 180
  private let sidebarMaximumWidth: CGFloat = 340
  private let inspectorMinimumWidth: CGFloat = 180
  private let inspectorIdealWidth: CGFloat = 260
  private let inspectorMaximumWidth: CGFloat = 300
  @Environment(LibraryViewModel.self) private var viewModel
  @State private var showingNewItem = false
  @State private var showingNewFolder = false
  @State private var showingAttachmentImporter = false
  @State private var pendingAttachmentImport: AttachmentImportRequest?
  @State private var isInspectorPresented = true
  @State private var selectedItemID: UUID?
  @State private var editingItem: LibraryItem?
  @State private var actionError: String?

  var body: some View {
    NavigationSplitView {
      List(selection: Bindable(viewModel).selectedFolder) {
        Section("Library") {
          HStack {
            Label("All Items", systemImage: "books.vertical")
            Spacer()
            Text(viewModel.items.filter { !$0.isTrashed }.count.formatted())
              .foregroundStyle(.secondary)
          }
          .tag(FolderSelection.allItems)
          HStack {
            Label("Unfiled", systemImage: "tray")
            Spacer()
            Text(viewModel.unfiledCount.formatted())
              .foregroundStyle(.secondary)
          }
          .tag(FolderSelection.unfiled)
          HStack {
            Label("Recycle Bin", systemImage: "trash")
            Spacer()
            Text(viewModel.trashCount.formatted())
              .foregroundStyle(.secondary)
          }
          .tag(FolderSelection.trash)
        }
        Section("Folders") {
          ForEach(viewModel.folders) { folder in
            HStack {
              Label(folder.name, systemImage: "folder")
              Spacer()
              Text(folder.itemCount.formatted())
                .foregroundStyle(.secondary)
            }
            .tag(FolderSelection.folder(folder.id))
          }
        }
      }
      .navigationSplitViewColumnWidth(
        min: sidebarMinimumWidth,
        ideal: sidebarMinimumWidth,
        max: sidebarMaximumWidth
      )
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button("New Folder", systemImage: "folder.badge.plus") {
            showingNewFolder = true
          }
          .labelStyle(.iconOnly)
          .help("Create a folder")
        }
      }
    } detail: {
      Group {
        if viewModel.filteredItems.isEmpty {
          Group {
            if viewModel.selectedFolder == .trash {
              ContentUnavailableView(
                "Recycle Bin Is Empty",
                systemImage: "trash",
                description: Text("Items you move to the recycle bin will appear here.")
              )
            } else if !viewModel.items.contains(where: { !$0.isTrashed }) {
              ContentUnavailableView(
                "Your Library Is Empty",
                systemImage: "books.vertical",
                description: Text("Add an item to start building your library.")
              )
            } else {
              ContentUnavailableView(
                "No Items",
                systemImage: "doc.text.magnifyingglass",
                description: Text("There are no items in this folder matching your search.")
              )
            }
          }
        } else {
          List(selection: $selectedItemID) {
            ForEach(viewModel.filteredItems) { item in
              ItemRow(item: item)
                .tag(item.id)
                .contextMenu {
                  if item.isTrashed {
                    Button("Restore Item", systemImage: "arrow.uturn.backward") {
                      actionError = viewModel.restore(item)
                    }
                  } else {
                    Button("Edit", systemImage: "pencil") {
                      editingItem = item
                    }
                    Menu("Add File", systemImage: "paperclip") {
                      ForEach(AttachmentRole.allCases) { role in
                        Button("\(role.menuTitle)…") {
                          pendingAttachmentImport = AttachmentImportRequest(itemID: item.id, role: role)
                          showingAttachmentImporter = true
                        }
                      }
                    }
                    if !item.attachments.isEmpty {
                      Menu("Open File", systemImage: "doc") {
                        ForEach(item.attachments) { attachment in
                          Button("\(attachment.role.menuTitle) · \(attachment.fileName)") {
                            Task {
                              actionError = await viewModel.openAttachment(attachment.id, for: item.id)
                            }
                          }
                        }
                      }
                    }
                    if !viewModel.folders.isEmpty {
                      Menu("Add to Folder", systemImage: "folder") {
                        ForEach(viewModel.folders) { folder in
                          Button(folder.name) {
                            actionError = viewModel.addItem(item, to: folder)
                          }
                          .disabled(item.folderIDs.contains(folder.id))
                        }
                      }
                    }
                    Button("Move to Recycle Bin", systemImage: "trash") {
                      actionError = viewModel.moveToTrash(item)
                    }
                  }
                }
            }
          }
          .inspector(isPresented: $isInspectorPresented) {
            Group {
              if let selectedItemID,
                 let item = viewModel.filteredItems.first(where: { $0.id == selectedItemID }) {
                ItemDetailView(item: item)
              } else {
                ContentUnavailableView(
                  "Select an Item",
                  systemImage: "book",
                  description: Text("Choose an item to see its details.")
                )
              }
            }
            .inspectorColumnWidth(
              min: inspectorMinimumWidth,
              ideal: inspectorIdealWidth,
              max: inspectorMaximumWidth
            )
          }
        }
      }
      .navigationTitle(selectedFolderTitle)
      .searchable(
        text: Bindable(viewModel).searchText,
        prompt: "Search items"
      )
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu("Add Item", systemImage: "plus") {
            Button("Add Manually", systemImage: "square.and.pencil") {
              showingNewItem = true
            }
          }
          .menuIndicator(.hidden)
          .labelStyle(.iconOnly)
          .help("Add an item")
        }
        ToolbarItem(placement: .automatic) {
          Button {
            isInspectorPresented.toggle()
          } label: {
            Image(systemName: "sidebar.trailing")
          }
          .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
          .accessibilityLabel(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
        DefaultToolbarItem(kind: .search, placement: .automatic)
      }
    }
    .frame(minWidth: 900, minHeight: 600)
    .task { viewModel.load() }
    .fileImporter(
      isPresented: $showingAttachmentImporter,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false
    ) { result in
      let request = pendingAttachmentImport
      pendingAttachmentImport = nil
      guard let request else { return }
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        Task {
          if let error = await viewModel.importAttachment(from: url, role: request.role, to: request.itemID) {
            actionError = error
          }
        }
      case .failure(let error):
        if (error as NSError).code != NSUserCancelledError {
          actionError = error.localizedDescription
        }
      }
    }
    .sheet(isPresented: $showingNewItem) {
      NewItemView { draft in
        viewModel.createItem(draft)
      }
    }
    .sheet(item: $editingItem) { item in
      NewItemView(item: item) { draft in
        viewModel.updateItem(item.id, from: draft)
      }
    }
    .sheet(isPresented: $showingNewFolder) {
      NewFolderView { name in
        viewModel.createFolder(named: name)
      }
    }
    .alert("Could Not Complete Action", isPresented: errorIsPresented) {
      Button("OK") {
        actionError = nil
        viewModel.clearLoadError()
      }
    } message: {
      Text(actionError ?? viewModel.loadError ?? "Please try again.")
    }
  }

  private var selectedFolderTitle: String {
    switch viewModel.selectedFolder ?? .allItems {
    case .allItems:
      "All Items"
    case .unfiled:
      "Unfiled"
    case .trash:
      "Recycle Bin"
    case .folder(let folderID):
      viewModel.folders.first { $0.id == folderID }?.name ?? "Folder"
    }
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { actionError != nil || viewModel.loadError != nil },
      set: {
        if !$0 {
          actionError = nil
          viewModel.clearLoadError()
        }
      }
    )
  }
}

private struct AttachmentImportRequest {
  let itemID: UUID
  let role: AttachmentRole
}

private extension AttachmentRole {
  var menuTitle: String {
    switch self {
    case .main: "Main File"
    case .supplementary: "Supplementary Material"
    case .code: "代码"
    case .data: "Data"
    case .other: "Other File"
    }
  }
}

private struct ItemRow: View {
  let item: LibraryItem

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(item.title)
        .lineLimit(2)
      HStack(spacing: 6) {
        if !item.authorNames.isEmpty {
          Text(item.authorNames.joined(separator: ", "))
        }
        if let year = item.publicationYear {
          Text("·")
          Text(String(year))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .padding(.vertical, 3)
  }
}
