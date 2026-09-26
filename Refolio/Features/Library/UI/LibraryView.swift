import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
  static let toggleDetailColumn = Notification.Name("RefolioToggleDetailColumn")
}

@Observable
final class SplitViewState {
  static let shared = SplitViewState()
  var isDetailCollapsed: Bool = false
}

struct LibraryView: View {
  private let sidebarMinimumWidth: CGFloat = 200
  private let sidebarIdealWidth: CGFloat = 220
  private let sidebarMaximumWidth: CGFloat = 280

  private let contentMinimumWidth: CGFloat = 280
  private let contentIdealWidth: CGFloat = 360

  private let detailMinimumWidth: CGFloat = 200
  private let detailIdealWidth: CGFloat = 300
  private let detailMaximumWidth: CGFloat = 600

  @Environment(LibraryViewModel.self) private var viewModel
  @Environment(\.openWindow) private var openWindow
  @State private var splitViewState = SplitViewState.shared
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var showingItemEditor = false
  @State private var showingDoiLookup = false
  @State private var pendingItemDraft: ItemDraft?
  @State private var showingNewFolder = false
  @State private var showingAttachmentImporter = false
  @State private var pendingAttachmentImport: AttachmentImportRequest?
  @State private var selectedItemID: UUID?
  @State private var lastItemClick: (id: UUID, time: TimeInterval)?
  @State private var editingItem: LibraryItem?
  @State private var actionError: String?

  private var selectedItem: LibraryItem? {
    guard let selectedItemID else { return nil }
    return viewModel.filteredItems.first(where: { $0.id == selectedItemID })
  }
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
    } content: {
      itemList
        .navigationTitle(selectedFolderTitle)
        .navigationSubtitle("\(viewModel.filteredItems.count) items")
        .navigationSplitViewColumnWidth(min: contentMinimumWidth, ideal: contentIdealWidth)
        .toolbar {
          ToolbarItemGroup(placement: .automatic) {
            Menu("Add Item", systemImage: "plus") {
              Button("Add Manually", systemImage: "square.and.pencil") {
                pendingItemDraft = nil
                showingItemEditor = true
              }
              Button("Add by DOI…", systemImage: "link") {
                showingDoiLookup = true
              }
            }
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .help("Add an item")

            Menu {
              Section("Main File") {
                Picker("Attachment", selection: Bindable(viewModel).attachmentFilter) {
                  ForEach(ItemAttachmentFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                      .tag(filter)
                  }
                }
              }

              if viewModel.attachmentFilter != .all {
                Divider()
                Button("Reset Filter") {
                  viewModel.attachmentFilter = .all
                }
              }
            } label: {
              Image(systemName: viewModel.attachmentFilter != .all ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .menuIndicator(.hidden)
            .help("Filter items")
          }

          ToolbarItem(placement: .automatic) {
            Button {
              NotificationCenter.default.post(name: .toggleDetailColumn, object: nil)
            } label: {
              Image(systemName: "sidebar.trailing")
            }
            .help(splitViewState.isDetailCollapsed ? "Show Details (⌘⌥0)" : "Hide Details (⌘⌥0)")
            .keyboardShortcut("0", modifiers: [.command, .option])
          }
        }
    } detail: {
      detailPanel
        .navigationSplitViewColumnWidth(
          min: detailMinimumWidth,
          ideal: detailIdealWidth,
          max: detailMaximumWidth
        )
        .toolbar {
          if !splitViewState.isDetailCollapsed {
            if let selectedItem {
              ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") {
                  editingItem = selectedItem
                }
                .labelStyle(.iconOnly)
                .help("Edit item")

                if let mainAttachment = selectedItem.attachments.first(where: { $0.role == .main }) {
                  Button("Read", systemImage: "book.pages") {
                    openAttachment(mainAttachment, for: selectedItem)
                  }
                  .labelStyle(.iconOnly)
                  .help("Read main file")
                }

                Button("Move to Recycle Bin", systemImage: "trash") {
                  actionError = viewModel.moveToTrash(selectedItem)
                }
                .labelStyle(.iconOnly)
                .help("Move to recycle bin")
              }
            }
          }
        }
        .searchable(
          text: Bindable(viewModel).searchText,
          prompt: "Search items"
        )
    }
    .background(SplitViewPriorityConfigurator())
    .task {
      viewModel.load()
      if selectedItemID == nil {
        selectedItemID = viewModel.filteredItems.first?.id
      }
    }
    .onChange(of: viewModel.selectedFolder) {
      selectedItemID = viewModel.filteredItems.first?.id
    }
    .onChange(of: viewModel.attachmentFilter) {
      if let current = selectedItemID, !viewModel.filteredItems.contains(where: { $0.id == current }) {
        selectedItemID = viewModel.filteredItems.first?.id
      }
    }
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
    .sheet(isPresented: $showingItemEditor, onDismiss: {
      pendingItemDraft = nil
    }) {
      ItemEditorView(initialDraft: pendingItemDraft) { draft in
        viewModel.createItem(draft)
      }
    }
    .sheet(isPresented: $showingDoiLookup, onDismiss: {
      if pendingItemDraft != nil {
        showingItemEditor = true
      }
    }) {
      DoiLookupView { draft in
        pendingItemDraft = draft
      }
    }
    .sheet(item: $editingItem) { item in
      ItemEditorView(item: item) { draft in
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
    .tint(Color(nsColor: .secondaryLabelColor))
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
            .simultaneousGesture(TapGesture(count: 2).onEnded {
              if let mainAttachment = item.attachments.first(where: { $0.role == .main }) {
                openAttachment(mainAttachment, for: item)
              }
            })
            .contextMenu {
              itemContextMenu(for: item)
            }
        }
      }
      .listStyle(.inset)
      .onChange(of: viewModel.filteredItems.first?.id) { _, firstID in
        if selectedItemID == nil {
          selectedItemID = firstID
        }
      }
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
        ItemDetailView(item: item) { attachment in
          openAttachment(attachment, for: item)
        }
      } else {
        ContentUnavailableView(
          "Select an Item",
          systemImage: "book",
          description: Text("Choose an item to see its details.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(nsColor: .textBackgroundColor))
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

extension AttachmentRole {
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
      HStack {
        Text(item.authorNames.isEmpty ? "Unknown Author" : item.authorNames.joined(separator: ", "))
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Spacer()
        if let year = item.publicationYear {
          Text(String(year))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Text(item.title)
        .font(.body)
        .lineLimit(2)
        .foregroundStyle(.primary)
      if let publication = item.publicationTitle, !publication.isEmpty {
        Text(publication)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }
}

private final class SplitConfigObserverView: NSView {
  private var hasConfigured = false
  private var detailConstraints: [NSLayoutConstraint] = []
  private var detailObservation: NSKeyValueObservation?
  private weak var splitVC: NSSplitViewController?
  private var mouseMonitor: Any?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window = self.window {
      setupMouseMonitor(for: window)
    } else {
      removeMouseMonitor()
    }
    NotificationCenter.default.removeObserver(self, name: .toggleDetailColumn, object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleToggleDetailNotification),
      name: .toggleDetailColumn,
      object: nil
    )
    NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowDidBecomeKey),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )
    applyConfiguration()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.applyConfiguration()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.applyConfiguration()
    }
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    if newWindow == nil {
      removeMouseMonitor()
    }
  }

  private func setupMouseMonitor(for window: NSWindow) {
    removeMouseMonitor()
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
      guard let self, let win = self.window, event.window == win else { return event }
      let clickPoint = event.locationInWindow
      if let hitView = win.contentView?.hitTest(clickPoint),
         hitView is NSTextView || hitView is NSTextField {
        return event
      }

      if let sidebarTV = self.findSidebarTableView(), !sidebarTV.refusesFirstResponder {
        sidebarTV.refusesFirstResponder = true
      }

      if let middleTV = self.findMiddleTableView() {
        let loc = middleTV.convert(clickPoint, from: nil)
        if middleTV.bounds.contains(loc) {
          if win.firstResponder !== middleTV {
            win.makeFirstResponder(middleTV)
          }
        }
      }

      DispatchQueue.main.async { [weak self] in
        guard let self, let win = self.window else { return }
        if let first = win.firstResponder as? NSView,
           first is NSTextView || first is NSTextField {
          return
        }
        if let middleTV = self.findMiddleTableView() {
          if win.firstResponder !== middleTV {
            win.makeFirstResponder(middleTV)
          }
        }
      }
      return event
    }
  }

  @objc private func handleWindowDidBecomeKey(notification: Notification) {
    guard let window = self.window,
          (notification.object as? NSWindow) == window else { return }
    if let middleTV = findMiddleTableView() {
      if window.firstResponder !== middleTV {
        window.makeFirstResponder(middleTV)
      }
    }
  }

  private func removeMouseMonitor() {
    if let monitor = mouseMonitor {
      NSEvent.removeMonitor(monitor)
      mouseMonitor = nil
    }
  }

  private func findSidebarTableView() -> NSTableView? {
    guard let window = self.window else { return nil }
    guard let splitView = findSplitView(in: window.contentView ?? self),
          let svc = (splitVC ?? (splitView.delegate as? NSSplitViewController)),
          svc.splitViewItems.count >= 1 else { return nil }
    let sidebarView = svc.splitViewItems[0].viewController.view
    return findTableView(in: sidebarView)
  }

  private func findMiddleTableView() -> NSTableView? {
    guard let window = self.window else { return nil }
    guard let splitView = findSplitView(in: window.contentView ?? self),
          let svc = (splitVC ?? (splitView.delegate as? NSSplitViewController)),
          svc.splitViewItems.count >= 2 else { return nil }
    let middleView = svc.splitViewItems[1].viewController.view
    return findTableView(in: middleView)
  }

  private func findTableView(in view: NSView) -> NSTableView? {
    if let tv = view as? NSTableView { return tv }
    for sub in view.subviews {
      if let tv = findTableView(in: sub) { return tv }
    }
    return nil
  }

  @objc private func handleToggleDetailNotification() {
    guard let window = self.window, window.isKeyWindow else { return }
    guard let svc = splitVC ?? (findSplitView(in: window.contentView ?? self)?.delegate as? NSSplitViewController),
          svc.splitViewItems.count >= 3 else { return }
    let detailItem = svc.splitViewItems[2]
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.25
      context.allowsImplicitAnimation = true
      detailItem.animator().isCollapsed.toggle()
    }
  }

  private func findSplitView(in current: NSView) -> NSSplitView? {
    if let sv = current as? NSSplitView { return sv }
    for sub in current.subviews {
      if let sv = findSplitView(in: sub) { return sv }
    }
    return nil
  }

  func applyConfiguration() {
    guard let window = self.window else { return }
    guard let splitView = findSplitView(in: window.contentView ?? self),
          let splitVC = splitView.delegate as? NSSplitViewController,
          splitVC.splitViewItems.count >= 3 else {
      return
    }

    self.splitVC = splitVC
    let items = splitVC.splitViewItems

    // 1: Middle Content (弹性：吸收全部窗口拉伸与收缩；不设上限，设下限)
    items[1].holdingPriority = NSLayoutConstraint.Priority(100)
    items[1].minimumThickness = 280
    items[1].maximumThickness = NSSplitViewItem.unspecifiedDimension

    // 2: Detail (固定：窗口拉伸时不随窗口变化；按用户要求严格限制在 200..600；仅允许按钮/快捷键收纳，禁止拖拽折叠)
    items[2].holdingPriority = NSLayoutConstraint.Priority(260)
    items[2].minimumThickness = 200
    items[2].maximumThickness = 600
    items[2].canCollapse = false

    let detailView = items[2].viewController.view
    if detailConstraints.isEmpty {
      let minC = detailView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
      let maxC = detailView.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
      minC.priority = NSLayoutConstraint.Priority(999)
      maxC.priority = NSLayoutConstraint.Priority(999)
      minC.isActive = !items[2].isCollapsed
      maxC.isActive = !items[2].isCollapsed
      detailConstraints = [minC, maxC]
    }

    if detailObservation == nil {
      detailObservation = items[2].observe(\.isCollapsed, options: [.initial, .new]) { [weak self] item, _ in
        DispatchQueue.main.async {
          SplitViewState.shared.isDetailCollapsed = item.isCollapsed
          self?.detailConstraints.forEach { $0.isActive = !item.isCollapsed }
        }
      }
    }

    // 让侧边栏拒绝成为第一响应者，防止其在聚焦时变蓝
    if let sidebarTV = findSidebarTableView() {
      sidebarTV.refusesFirstResponder = true
    }

    // 初始化重置为用户指定的 300 理想宽度
    if !hasConfigured && splitView.frame.width > 700 {
      hasConfigured = true
      let targetX = splitView.frame.width - 300
      splitView.setPosition(targetX, ofDividerAt: 1)
    }

    // 默认让文献列表持有焦点
    if let middleTV = findMiddleTableView() {
      if window.firstResponder !== middleTV {
        window.makeFirstResponder(middleTV)
      }
    }
  }

  deinit {
    removeMouseMonitor()
    NotificationCenter.default.removeObserver(self)
    detailObservation?.invalidate()
  }
}

private struct SplitViewPriorityConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> SplitConfigObserverView {
    SplitConfigObserverView()
  }

  func updateNSView(_ nsView: SplitConfigObserverView, context: Context) {
    nsView.applyConfiguration()
  }
}
