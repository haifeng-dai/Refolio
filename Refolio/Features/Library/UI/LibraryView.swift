import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  private let sidebarMinimumWidth: CGFloat = 180
  private let sidebarIdealWidth: CGFloat = 220
  private let sidebarMaximumWidth: CGFloat = 280
  private let inspectorMinimumWidth: CGFloat = 300
  private let inspectorIdealWidth: CGFloat = 320
  private let inspectorMaximumWidth: CGFloat = 480

  @Environment(LibraryViewModel.self) private var viewModel
  @Environment(\.openWindow) private var openWindow
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var showingNewItem = false
  @State private var showingNewFolder = false
  @State private var showingAttachmentImporter = false
  @State private var pendingAttachmentImport: AttachmentImportRequest?
  @State private var isDetailPresented = true
  @State private var selectedItemID: UUID?
  @State private var lastItemClick: (id: UUID, time: TimeInterval)?
  @State private var editingItem: LibraryItem?
  @State private var actionError: String?

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebar
        .navigationTitle("Library")
        .navigationSplitViewColumnWidth(
          min: sidebarMinimumWidth,
          ideal: sidebarIdealWidth,
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
      itemList
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(selectedFolderTitle)
        .toolbarTitleDisplayMode(.inline)
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
              isDetailPresented.toggle()
            } label: {
              Image(systemName: "sidebar.trailing")
            }
            .help(isDetailPresented ? "Hide Details" : "Show Details")
            .accessibilityLabel(isDetailPresented ? "Hide Details" : "Show Details")
          }
          DefaultToolbarItem(kind: .search, placement: .automatic)
        }
        .inspector(isPresented: $isDetailPresented) {
          detailPanel
            .inspectorColumnWidth(
              min: inspectorMinimumWidth,
              ideal: inspectorIdealWidth,
              max: inspectorMaximumWidth
            )
            .interactiveDismissDisabled()
        }
    }
    .frame(minWidth: 980, minHeight: 600)
    .task { viewModel.load() }
    .searchable(
      text: Bindable(viewModel).searchText,
      prompt: "Search items"
    )
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

  private var sidebar: some View {
    List(selection: Bindable(viewModel).selectedFolder) {
      Section("Library") {
        sidebarRow(
          title: "All Items",
          systemImage: "books.vertical",
          count: viewModel.items.filter { !$0.isTrashed }.count,
          selection: .allItems
        )
        sidebarRow(
          title: "Unfiled",
          systemImage: "tray",
          count: viewModel.unfiledCount,
          selection: .unfiled
        )
        sidebarRow(
          title: "Recycle Bin",
          systemImage: "trash",
          count: viewModel.trashCount,
          selection: .trash
        )
      }
      Section("Folders") {
        ForEach(viewModel.folders) { folder in
          sidebarRow(
            title: folder.name,
            systemImage: "folder",
            count: folder.itemCount,
            selection: .folder(folder.id)
          )
        }
      }
    }
    .listStyle(.sidebar)
  }

  private func sidebarRow(
    title: String,
    systemImage: String,
    count: Int,
    selection: FolderSelection
  ) -> some View {
    HStack {
      Label(title, systemImage: systemImage)
      Spacer()
      Text(count.formatted())
        .foregroundStyle(.secondary)
    }
    .tag(selection)
  }

  @ViewBuilder
  private var itemList: some View {
    if viewModel.filteredItems.isEmpty {
      emptyState
    } else {
      List(selection: $selectedItemID) {
        ForEach(viewModel.filteredItems) { item in
          ItemRow(item: item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(item.id)
            .onTapGesture {
              handleItemClick(item)
            }
            .contextMenu {
              itemContextMenu(for: item)
            }
        }
      }
      .listStyle(.inset)
    }
  }

  @ViewBuilder
  private var emptyState: some View {
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

  @ViewBuilder
  private var detailPanel: some View {
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private func itemContextMenu(for item: LibraryItem) -> some View {
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
              openAttachment(attachment, for: item)
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

  private func openAttachment(_ attachment: LibraryAttachment, for item: LibraryItem) {
    Task {
      do {
        let disposition = try await viewModel.openAttachment(attachment.id, for: item.id)
        if disposition == .inAppPDF {
          openWindow(
            id: "pdf-reader",
            value: PDFReaderRequest(itemID: item.id, attachmentID: attachment.id)
          )
        }
      } catch {
        actionError = error.localizedDescription
      }
    }
  }

  private func handleItemClick(_ item: LibraryItem) {
    selectedItemID = item.id
    let now = ProcessInfo.processInfo.systemUptime
    if let lastItemClick,
       lastItemClick.id == item.id,
       now - lastItemClick.time <= NSEvent.doubleClickInterval {
      self.lastItemClick = nil
      guard let mainAttachment = item.attachments.first(where: { $0.role == .main }) else {
        actionError = "This item has no main file."
        return
      }
      openAttachment(mainAttachment, for: item)
    } else {
      lastItemClick = (item.id, now)
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
