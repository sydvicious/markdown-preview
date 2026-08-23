//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    private let disableLiveFileMonitoring: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var commandCenter: MarkdownAppCommandCenter
    @EnvironmentObject private var fileOpenState: FileOpenState
    @State private var pendingSearchFocusTask: Task<Void, Never>?
    @StateObject private var viewModel: ContentViewModel
    @StateObject private var previewSelectionSynchronizer = PreviewSelectionSynchronizer()
    @FocusState private var focusedSearchField: SearchField?

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        showsSourceInPreview: Bool = false,
        disablePersistenceRestore: Bool = false,
        disableLiveFileMonitoring: Bool = false
    ) {
        _viewModel = StateObject(
            wrappedValue: ContentViewModel(
                previewFiles: previewFiles,
                selectedPreviewFileID: selectedPreviewFileID,
                showsSourceInPreview: showsSourceInPreview,
                disablePersistenceRestore: disablePersistenceRestore
            )
        )
        self.disableLiveFileMonitoring = disableLiveFileMonitoring
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $viewModel.preferredCompactColumn) {
            NavigationStack {
                sidebarPanel
                    .modifier(SidebarTitleInSingleColumn(isActive: usesSingleColumnNavigation))
                    // On macOS the list's add/remove controls live in a bar
                    // beneath the list (`sidebarListActionBar`) rather than in
                    // the window toolbar, so the toolbar cannot evict them.
                    #if os(iOS)
                    .toolbar {
                        ToolbarItem(placement: openButtonPlacement) {
                            Button {
                                viewModel.isImporterPresented = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Open")
                            .accessibilityIdentifier("Open")
                        }
                        if store.selectedDocumentID != nil {
                            ToolbarItem(placement: removeButtonPlacement) {
                                removeFromListButton
                            }
                        }
                    }
                    #endif
            }
        } detail: {
            NavigationStack {
                detailPanel
                    .modifier(
                        DetailPaneWidthReader { width in
                            viewModel.updateDetailSearchPlacement(forDetailPaneWidth: width)
                        }
                    )
                    .navigationTitle(viewModel.detailNavigationTitle())
                    .modifier(InlineTitleOnIOS())
                    .toolbar {
                        if store.currentDocument != nil, showsToolbarDetailSearch {
                            ToolbarItem(placement: detailSearchToolbarPlacement) {
                                detailSearchToolbarItem
                            }
                        }
                        ToolbarItemGroup(placement: viewButtonPlacement) {
                            if let selectedDocumentID = store.selectedDocumentID {
                                Button {
                                    viewModel.decreaseSelectedTextSize()
                                } label: {
                                    Image(systemName: "textformat.size.smaller")
                                }
                                .disabled(!store.canDecreaseTextSize(for: selectedDocumentID))
                                .accessibilityLabel("Decrease Text Size")
                                .accessibilityIdentifier("DecreaseTextSize")

                                Button {
                                    viewModel.increaseSelectedTextSize()
                                } label: {
                                    Image(systemName: "textformat.size.larger")
                                }
                                .disabled(!store.canIncreaseTextSize(for: selectedDocumentID))
                                .accessibilityLabel("Increase Text Size")
                                .accessibilityIdentifier("IncreaseTextSize")
                            }
                        }
                    }
            }
        }
        .background(macFirstResponderSinkBackground)
        #if os(macOS)
        .onExitCommand(perform: viewModel.cancelFocusedSearch)
        #endif
        #if os(macOS)
        .fileImporter(
            isPresented: $viewModel.isImporterPresented,
            allowedContentTypes: MarkdownFile.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            viewModel.handleImport(result, isCompactWidth: usesSingleColumnNavigation)
        }
        #else
        .sheet(isPresented: $viewModel.isImporterPresented) {
            MarkdownDocumentPicker { url in
                viewModel.load(url: url, isCompactWidth: usesSingleColumnNavigation)
                viewModel.isImporterPresented = false
            } onCancel: {
                viewModel.isImporterPresented = false
            }
        }
        #endif
        #if !os(macOS)
        .sheet(isPresented: $viewModel.isInitialOpenSheetPresented) {
            initialOpenSheet
        }
        #endif
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.loadDroppedProviders(providers, isCompactWidth: usesSingleColumnNavigation)
        }
        #endif
        .alert("Unable to Open File", isPresented: .constant(viewModel.openErrorMessage != nil)) {
            Button("OK") { viewModel.openErrorMessage = nil }
        } message: {
            Text(viewModel.openErrorMessage ?? "Unknown error")
        }
        .alert(
            "File No Longer Available",
            isPresented: Binding(
                get: { store.missingActiveDocumentAlert != nil },
                set: { if !$0 { store.missingActiveDocumentAlert = nil } }
            ),
            presenting: store.missingActiveDocumentAlert
        ) { alert in
            Button("OK") {
                viewModel.acknowledgeMissingActiveDocument(isCompactWidth: usesSingleColumnNavigation)
            }
        } message: { alert in
            Text("\"\(alert.fileName)\" is no longer available.")
        }
        .onChange(of: store.openedDocuments) { _, _ in
            viewModel.onDocumentsChanged()
            refreshDetailSearch()
            presentInitialOpenPromptIfNeeded()
            syncCommandCenter()
        }
        .onChange(of: store.selectedDocumentID) { _, _ in
            previewSelectedText = nil
            viewModel.onSelectionChanged()
            refreshDetailSearch()
            syncCommandCenter()
        }
        .onChange(of: store.textSizesByDocumentID) { _, _ in
            store.persistTextSizes()
            syncCommandCenter()
        }
        .onChange(of: store.selectionsByDocumentID) { _, _ in
            syncCommandCenter()
        }
        .onChange(of: detailSearch.resultCount) { _, _ in
            syncCommandCenter()
        }
        .onChange(of: previewSelectedText) { _, _ in
            syncCommandCenter()
        }
        .onChange(of: viewModel.detailMode) { _, _ in
            previewSelectedText = nil
            syncCommandCenter()
        }
        .onChange(of: focusedSearchField) { _, newValue in
            search.focusedField = newValue
            #if os(macOS)
            // Taking focus is the moment the user opts into the shared find
            // buffer, so this is where a term another app published gets picked
            // up — not on activation.
            if newValue != nil {
                adoptSystemFindQueryIfChanged()
            }
            #endif
            syncCommandCenter()
        }
        // Bridge the View's size class into the view model so its command/focus
        // logic can read it without the SwiftUI environment.
        .onChange(of: usesSingleColumnNavigation) { _, newValue in
            viewModel.usesSingleColumnNavigation = newValue
        }
        // Apply focus moves requested by the view model to the View's @FocusState.
        .onChange(of: viewModel.focusRequest) { _, request in
            guard let request else { return }
            applyFocus(request.field)
        }
        // Keep the view model's foreground flag in sync so list filtering only
        // hides files while the app is active.
        .onChange(of: scenePhase) { _, _ in
            viewModel.isSearchHostAppActive = isSearchHostAppActive
        }
        .onAppear {
            viewModel.usesSingleColumnNavigation = usesSingleColumnNavigation
            viewModel.isSearchHostAppActive = isSearchHostAppActive
            viewModel.restorePersistedDocumentsIfNeeded(isCompactWidth: usesSingleColumnNavigation)
            refreshDetailSearch()
            presentInitialOpenPromptIfNeeded()
            syncCommandCenter()
            #if os(iOS)
            if !disableLiveFileMonitoring {
                store.checkActiveDocumentForChanges(isCompactWidth: usesSingleColumnNavigation)
                store.checkAllDocumentsForChanges(isCompactWidth: usesSingleColumnNavigation)
            }
            #endif
        }
        .onDisappear {
            pendingSearchFocusTask?.cancel()
            commandCenter.reset()
        }
        #if os(iOS)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            if !disableLiveFileMonitoring {
                store.checkActiveDocumentForChanges(isCompactWidth: usesSingleColumnNavigation)
                store.checkAllDocumentsForChanges(isCompactWidth: usesSingleColumnNavigation)
            }
        }
        #endif
        .onReceive(fileOpenState.$pendingURLs.filter { !$0.isEmpty }) { urls in
            viewModel.openPendingURLs(urls, isCompactWidth: usesSingleColumnNavigation)
            fileOpenState.pendingURLs = []
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if !disableLiveFileMonitoring {
                store.checkActiveDocumentForChanges(isCompactWidth: usesSingleColumnNavigation)
            }
        }
        .onReceive(Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()) { _ in
            if !disableLiveFileMonitoring {
                store.checkAllDocumentsForChanges(isCompactWidth: usesSingleColumnNavigation)
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            listSearchBar
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Group {
                if !store.didRestoreDocuments {
                    ProgressView("Loading Files")
                } else if store.sortedDocuments.isEmpty {
                    Text("No files loaded")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if viewModel.isListSearchFiltering, viewModel.filteredDocumentsCount == 0 {
                    Text("No matching files")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    #if os(macOS)
                    List(selection: Binding(
                        get: { store.selectedDocumentID },
                        set: { store.selectedDocumentID = $0 }
                    )) {
                        ForEach(viewModel.filteredGroupedDocumentsByParentDirectory) { section in
                            Section {
                                ForEach(section.documents) { document in
                                    sidebarDocumentRow(document)
                                }
                            } header: {
                                Text(section.label)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                    }
                    .onDeleteCommand(perform: viewModel.removeSelectedDocumentFromList)
                    .contextMenu(forSelectionType: DocumentSessionStore.OpenedDocument.ID.self) { ids in
                        Button {
                            ids.forEach { viewModel.removeDocumentFromList(id: $0) }
                        } label: {
                            Label("Remove from List", systemImage: "xmark.circle")
                        }
                    }
                    #else
                    List {
                        ForEach(viewModel.filteredSortedDocuments) { document in
                            sidebarDocumentRow(document)
                        }
                        .onDelete { offsets in
                            deleteFilteredDocuments(at: offsets)
                        }
                    }
                    .id(trimmedSearchText)
                    #endif
                }
            }

            #if os(macOS)
            sidebarListActionBar
            #endif
        }
    }

    #if os(macOS)
    /// Add/remove controls for the file list, in the `+`/`−` bar beneath a list
    /// that the rest of macOS uses (Login Items, Users & Groups, the Finder
    /// sidebar editor).
    ///
    /// These were window toolbar items until the toolbar proved it could take
    /// them away: below a sidebar width there was no room for both the sidebar
    /// toggle and the remove button, so AppKit evicted the remove button to the
    /// detail toolbar's `»` overflow menu — detached from the list it acts on,
    /// and unreachable once there. Nothing in the sidebar's own content can be
    /// evicted, so putting them here removes the failure mode rather than
    /// bounding it.
    private var sidebarListActionBar: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.isImporterPresented = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .accessibilityLabel("Open")
            .accessibilityIdentifier("Open")

            Button {
                viewModel.removeSelectedDocumentFromList()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .disabled(store.selectedDocumentID == nil)
            .accessibilityLabel("Remove from List")
            .accessibilityIdentifier("RemoveFromList")

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .overlay(alignment: .top) {
            Divider()
        }
    }
    #endif

    private func sidebarDocumentRow(_ document: DocumentSessionStore.OpenedDocument) -> some View {
        HStack {
            Text(document.file.fileName)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .modifier(SidebarRowSelectionTag(documentID: document.id))
        .modifier(SidebarRowTapAction(
            isCompactWidth: usesSingleColumnNavigation,
            action: {
                store.selectedDocumentID = document.id
                if usesSingleColumnNavigation {
                    viewModel.preferredCompactColumn = .detail
                }
            }
        ))
        #if os(macOS)
        // On macOS the row context menu is provided by the List via
        // `.contextMenu(forSelectionType:)`, which is far more reliable than a
        // per-row `.contextMenu` combined with `.tag()`-based selection.
        .help(viewModel.tooltipPath(for: document.file.url))
        #else
        .contextMenu {
            Button {
                viewModel.removeDocumentFromList(id: document.id)
            } label: {
                Label("Remove from List", systemImage: "xmark.circle")
            }
        }
        .swipeActions {
            Button {
                viewModel.removeDocumentFromList(id: document.id)
            } label: {
                Label("Remove", systemImage: "xmark.circle")
            }
            .tint(.gray)
        }
        #endif
    }

    private var detailPanel: some View {
        guard store.currentDocument != nil else {
            return AnyView(
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        return AnyView(
            VStack(spacing: 0) {
                detailModePicker
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if showsToolbarDetailSearch == false {
                    detailSearchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                Group {
                    if viewModel.detailMode == .preview {
                        previewPanel
                    } else {
                        sourcePanel
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    #if !os(macOS)
    private var initialOpenSheet: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No files loaded", systemImage: "doc.text")
            } description: {
                Text("Open a .md file")
            } actions: {
                Button("Open Markdown File") {
                    viewModel.isInitialOpenSheetPresented = false
                    viewModel.isImporterPresented = true
                }
                Button("Not now", role: .cancel) {
                    viewModel.isInitialOpenSheetPresented = false
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    #endif

    private var sourcePanel: some View {
        Group {
            if let document = store.currentDocument {
                MarkdownSourceView(
                    contents: document.file.contents,
                    textSize: store.textSize(for: document.id),
                    selections: Binding(
                        get: { store.selections(for: document.id) },
                        set: { store.setSelections($0, for: document.id, text: document.file.contents) }
                    ),
                    onSearchSelection: searchForSelection
                )
            }
        }
    }

    private var previewPanel: some View {
        Group {
            if let document = store.currentDocument {
                MarkdownPreviewView(
                    source: document.file.contents,
                    baseURL: document.file.url.deletingLastPathComponent(),
                    textSize: store.textSize(for: document.id),
                    selections: Binding(
                        get: { store.selections(for: document.id) },
                        set: { store.setSelections($0, for: document.id, text: document.file.contents) }
                    ),
                    selectionSynchronizer: previewSelectionSynchronizer,
                    onSelectedTextChange: { previewSelectedText = $0 },
                    onSelectedRangesChange: { ranges in
                        store.setSelections(ranges, for: document.id, text: document.file.contents)
                    },
                    onSearchSelection: searchForSelection
                )
            }
        }
    }

    private var detailModePicker: some View {
        Picker("View", selection: detailModeBinding) {
            Text("Preview").tag(ContentViewModel.DetailMode.preview)
            Text("Source").tag(ContentViewModel.DetailMode.source)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("View")
        .accessibilityIdentifier("DetailModePicker")
    }

    private var detailModeBinding: Binding<ContentViewModel.DetailMode> {
        Binding(
            get: { viewModel.detailMode },
            set: { setDetailMode($0) }
        )
    }

    private func setDetailMode(_ nextMode: ContentViewModel.DetailMode) {
        guard nextMode != viewModel.detailMode else { return }
        guard viewModel.detailMode == .preview, nextMode == .source else {
            Task { @MainActor in
                viewModel.detailMode = nextMode
            }
            return
        }

        previewSelectionSynchronizer.flushSelection {
            Task { @MainActor in
                viewModel.detailMode = nextMode
            }
        }
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    /// Whether the in-document search lives in the title bar rather than in the
    /// detail pane. Both platforms answer this by width: on macOS from the
    /// detail pane's measured width, so a narrow window moves the search into
    /// the pane instead of letting the toolbar bury it in the `»` overflow menu
    /// where the field cannot be used at all; on iOS from the size class, so a
    /// compact window gets the inline bar. iPhone is compact almost always and
    /// so is unaffected by the switch from an idiom test to a width test.
    private var showsToolbarDetailSearch: Bool {
        #if os(macOS)
        viewModel.detailSearchFitsInToolbar
        #else
        !isCompactWidth
        #endif
    }

    /// Whether the layout shows one column at a time, so a row tap has to push
    /// to the detail column and Back has to return to the list.
    ///
    /// This follows the horizontal size class alone. It deliberately does not
    /// test the idiom: `NavigationSplitView` collapses to a single column at
    /// compact width on iPad too — in a narrow Stage Manager or Split View
    /// window — and gating this on `.phone` left that case with a file list and
    /// no way to reach the document, since nothing ever moved the preferred
    /// column to `.detail`. Compact width is the whole condition.
    private var usesSingleColumnNavigation: Bool {
        #if os(iOS)
        isCompactWidth
        #else
        false
        #endif
    }

    #if os(iOS)
    private var openButtonPlacement: ToolbarItemPlacement { .topBarTrailing }
    #endif

    private var viewButtonPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    private var detailSearchToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .principal
        #endif
    }

    #if os(iOS)
    /// iOS keeps removal in the navigation bar. macOS puts it in
    /// `sidebarListActionBar` instead, so this button exists only here.
    private var removeFromListButton: some View {
        Button {
            viewModel.removeSelectedDocumentFromList()
        } label: {
            Image(systemName: "xmark.circle")
        }
        .disabled(store.selectedDocumentID == nil)
        .accessibilityLabel("Remove from List")
        .accessibilityIdentifier("RemoveFromList")
    }

    private var removeButtonPlacement: ToolbarItemPlacement { .topBarTrailing }
    #endif

    @ViewBuilder
    private var macFirstResponderSinkBackground: some View {
        #if os(macOS)
        MacFirstResponderSinkView(
            onDelete: viewModel.removeSelectedDocumentFromList,
            onSearchFieldFocusChange: { field in
                // AppKit is the source of truth for which search field is
                // focused; `@FocusState` misses the toolbar-hosted field
                // entirely (see MacFirstResponderSinkNSView). Do the focus
                // bookkeeping directly rather than via `focusedSearchField`,
                // whose onChange may never fire for these transitions.
                search.focusedField = field
                if field != nil {
                    adoptSystemFindQueryIfChanged()
                }
                syncCommandCenter()
            }
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        #endif
    }

    private func syncCommandCenter() {
        commandCenter.update(
            canFind: viewModel.canFind,
            handleFind: viewModel.handleFindCommand,
            canProjectFind: viewModel.canProjectFind,
            handleProjectFind: viewModel.focusListSearch,
            canUseSelectionForFind: viewModel.canUseSelectionForFind,
            handleUseSelectionForFind: viewModel.useCurrentSelectionForFind,
            canFindNext: viewModel.canFindNext,
            handleFindNext: { viewModel.navigateDetailSearch(.forward) },
            canFindPrevious: viewModel.canFindPrevious,
            handleFindPrevious: { viewModel.navigateDetailSearch(.backward) },
            canIncreaseTextSize: viewModel.canIncreaseTextSize,
            handleIncreaseTextSize: viewModel.increaseSelectedTextSize,
            canDecreaseTextSize: viewModel.canDecreaseTextSize,
            handleDecreaseTextSize: viewModel.decreaseSelectedTextSize,
            handleCancelSearch: viewModel.cancelFocusedSearch,
            canRemoveFromList: viewModel.canRemoveFromList,
            handleRemoveFromList: viewModel.removeSelectedDocumentFromList
        )
    }

    private var listSearchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(Self.listSearchFieldPlaceholder, text: searchBinding)
                    .searchFieldTextInputBehavior()
                    .focused($focusedSearchField, equals: .list)
                    .accessibilityIdentifier("ListSearchField")

                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .opacity(trimmedSearchText.isEmpty ? 0 : 1)
                }
                .buttonStyle(.plain)
                .disabled(trimmedSearchText.isEmpty)
                .accessibilityHidden(trimmedSearchText.isEmpty)
                .accessibilityLabel("Clear File Search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(searchFieldBackground)

            if search.focusedField == .list, !search.listSearchSuggestions.isEmpty {
                searchSuggestionsRow(search.listSearchSuggestions) { suggestion in
                    setSearchText(suggestion)
                }
            }
        }
    }

    private var detailSearchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                detailSearchField(compact: false)
                detailSearchStatusLabel
                detailSearchNavigationButtons
            }

            if search.focusedField == .detail, !search.detailSearchSuggestions.isEmpty {
                searchSuggestionsRow(search.detailSearchSuggestions) { suggestion in
                    setSearchText(suggestion, focus: .detail)
                }
            }
        }
    }

    /// Floor for the in-document search field, in the title bar and in the
    /// detail pane alike. The field never draws narrower than this; in the title
    /// bar the file name truncates instead.
    ///
    /// In the title bar on macOS this is effectively a fixed width: `AppKit`
    /// sizes a custom `NSToolbarItem` to its view's fitting width and never
    /// stretches it, so the `maxWidth: .infinity` below buys nothing there and
    /// blank title-bar space to the field's left is expected. (Only
    /// `NSSearchToolbarItem` — what `.searchable` produces — is resizable by the
    /// toolbar, and adopting it was considered and declined.) The flexible width
    /// still matters on iPadOS, where the field is a `.principal` navigation-bar
    /// item and does expand.
    ///
    /// The floor also matters in the detail pane, where the window's minimum
    /// width is what normally keeps the bar wide enough — but the sidebar
    /// divider can still be dragged rightwards and squeeze the pane on its own.
    /// Placeholder strings for the two search fields. Shared with the AppKit
    /// responder classifier in `MacFirstResponderSinkNSView`, which identifies a
    /// focused field by its placeholder — keep them unique.
    fileprivate static let listSearchFieldPlaceholder = "Search files"
    fileprivate static let detailSearchFieldPlaceholder = "Search in file"

    private static let searchFieldMinimumWidth: CGFloat = 180

    /// Upper bound for the search field's width, which is a flexible `.infinity`
    /// on iPadOS and unset on macOS.
    ///
    /// Asking for `.infinity` inside an `NSToolbarItem` does not merely fail to
    /// stretch the field — it makes the hosting view report an unbounded fitting
    /// width, and `NSToolbar` sizes items by fitting width. The toolbar then
    /// believes the search item needs the entire bar and pushes other items into
    /// the `»` overflow menu at every window size, including a full-width
    /// window. Leaving it unset lets the item report the width it actually
    /// draws. On iPadOS the field is a `.principal` navigation-bar item, where
    /// the flexible width does apply and is wanted.
    private static func searchFieldMaximumWidth(compact: Bool) -> CGFloat? {
        #if os(macOS)
        return nil
        #else
        return compact ? .infinity : nil
        #endif
    }

    private var detailSearchToolbarItem: some View {
        HStack(spacing: 8) {
            detailSearchField(compact: true)
            detailSearchStatusLabel
                .fixedSize()
            detailSearchNavigationButtons
                .fixedSize()
        }
        .modifier(FillsAvailableWidthOnIOS())
    }

    private func detailSearchField(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(Self.detailSearchFieldPlaceholder, text: searchBinding)
                .searchFieldTextInputBehavior()
                .focused($focusedSearchField, equals: .detail)
                .onSubmit {
                    viewModel.navigateDetailSearch(.forward)
                }
                .accessibilityIdentifier("DetailSearchField")

            Button {
                viewModel.clearSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .opacity(searchText.isEmpty ? 0 : 1)
            }
            .buttonStyle(.plain)
            .disabled(searchText.isEmpty)
            .accessibilityHidden(searchText.isEmpty)
            .accessibilityLabel("Clear Detail Search")
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 10)
        .frame(
            minWidth: Self.searchFieldMinimumWidth,
            maxWidth: Self.searchFieldMaximumWidth(compact: compact),
            alignment: .leading
        )
        .background(searchFieldBackground)
        .modifier(CompactControlSize(isCompact: compact))
        .layoutPriority(compact ? 1 : 0)
    }

    private var detailSearchStatusLabel: some View {
        Text(search.detailSearchStatusText ?? "0 results")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, alignment: .trailing)
    }

    private var detailSearchNavigationButtons: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.navigateDetailSearch(.backward)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(detailSearch.resultCount == 0)
            .accessibilityLabel("Previous Result")

            Button {
                viewModel.navigateDetailSearch(.forward)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(detailSearch.resultCount == 0)
            .accessibilityLabel("Next Result")
        }
        .modifier(CompactControlSize(isCompact: showsToolbarDetailSearch))
    }

    private var searchFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.thinMaterial)
    }

    private func searchSuggestionsRow(_ suggestions: [String], onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        onSelect(suggestion)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }


    private func presentInitialOpenPromptIfNeeded() {
        #if os(macOS)
        viewModel.scheduleStartupImporterIfNeeded()
        #else
        _ = viewModel.presentInitialOpenPromptIfNeeded()
        #endif
    }

    private var store: DocumentSessionStore { viewModel.store }
    private var search: SearchViewModel { viewModel.search }

    // The search state and data logic live in `SearchViewModel`; the View reads
    // them through these accessors and keeps only keyboard-focus handling.
    private var searchText: String { search.searchText }
    private var detailSearch: MarkdownSearchSession { search.detailSearch }
    private var previewSelectedText: String? {
        get { search.previewSelectedText }
        nonmutating set { search.previewSelectedText = newValue }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { setSearchText($0) }
        )
    }

    private var trimmedSearchText: String {
        search.trimmedSearchText
    }

    // Computed here (it reads the SwiftUI scene phase / `NSApp`) and pushed into
    // the view model, which owns the list-filtering derived from it.
    private var isSearchHostAppActive: Bool {
        guard scenePhase == .active else { return false }
        #if os(macOS)
        return NSApp.isActive
        #else
        return true
        #endif
    }

    #if os(iOS)
    /// Backs the iOS list's swipe-to-delete. macOS removes through
    /// `sidebarListActionBar`, the row context menu, or the Delete key.
    private func deleteFilteredDocuments(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { viewModel.filteredSortedDocuments[safe: $0]?.id }
        idsToDelete.forEach { viewModel.removeDocumentFromList(id: $0) }
    }
    #endif

    /// Sets the shared search text (used by the search-field bindings and the
    /// suggestion taps) and optionally moves keyboard focus.
    private func setSearchText(_ query: String, focus: SearchField? = nil) {
        search.setSearchText(query)
        if let focus {
            applyFocus(focus)
        }
    }

    #if os(macOS)
    private func adoptSystemFindQueryIfChanged() {
        search.adoptSystemFindQueryIfChanged()
    }
    #endif

    private func refreshDetailSearch() {
        search.refreshDetailSearch()
    }

    /// Applies a view-model focus request to the View's `@FocusState`. On macOS
    /// the assignment is retried a few times because SwiftUI can drop a
    /// programmatic focus change before the field is ready to receive it.
    private func applyFocus(_ field: SearchField?) {
        pendingSearchFocusTask?.cancel()
        focusedSearchField = field

        #if os(macOS)
        guard field != nil else { return }
        pendingSearchFocusTask = Task { @MainActor in
            let delays: [UInt64] = [0, 20_000_000, 80_000_000]
            for delay in delays {
                if delay == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                focusedSearchField = field
            }
        }
        #endif
    }

    /// Runs the shared search for text chosen from a selection's "Search" edit-menu
    /// action. Does not steal keyboard focus, so the highlighted match stays visible
    /// instead of being covered by the on-screen keyboard.
    private func searchForSelection(_ rawText: String) {
        search.searchForSelection(rawText)
    }

}

/// Reports the detail pane's width so the view model can decide whether the
/// in-document search still fits in the title bar. macOS only — on iOS that
/// placement follows the idiom, not the width, so the measurement would be dead
/// weight.
/// Lets a navigation-bar item take the width offered to it on iOS. Inert on
/// macOS, where a toolbar item is sized to what it draws — see
/// `ContentView.searchFieldMaximumWidth(compact:)` for why asking for more there
/// is actively harmful.
private struct FillsAvailableWidthOnIOS: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

private struct DetailPaneWidthReader: ViewModifier {
    let onWidthChange: (CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            onWidthChange(width)
        }
        #else
        content
        #endif
    }
}

private struct InlineTitleOnIOS: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}

private struct SidebarTitleInSingleColumn: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if isActive {
            content
                .navigationTitle("MarkdownPreview")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct SidebarRowSelectionTag: ViewModifier {
    let documentID: String

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.tag(documentID)
        #else
        content
        #endif
    }
}

private struct SidebarRowTapAction: ViewModifier {
    let isCompactWidth: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.onTapGesture(perform: action)
        #endif
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension View {
    @ViewBuilder
    func searchFieldTextInputBehavior() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

private struct CompactControlSize: ViewModifier {
    let isCompact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCompact {
            content.controlSize(.small)
        } else {
            content
        }
    }
}

#if os(macOS)
private struct MacFirstResponderSinkView: NSViewRepresentable {
    var onDelete: () -> Void = {}
    var onSearchFieldFocusChange: (SearchField?) -> Void = { _ in }

    func makeNSView(context: Context) -> MacFirstResponderSinkNSView {
        let view = MacFirstResponderSinkNSView(frame: .zero)
        view.setAccessibilityElement(false)
        view.onDelete = onDelete
        view.onSearchFieldFocusChange = onSearchFieldFocusChange
        return view
    }

    func updateNSView(_ nsView: MacFirstResponderSinkNSView, context: Context) {
        nsView.onDelete = onDelete
        nsView.onSearchFieldFocusChange = onSearchFieldFocusChange
    }
}

private final class MacFirstResponderSinkNSView: NSView {
    var onDelete: () -> Void = {}
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    /// Reports which search field, if any, holds the AppKit first responder.
    ///
    /// SwiftUI's `@FocusState` misses focus changes in the toolbar-hosted
    /// "Search in file" field entirely — verified 2026-08-22: the field's editor
    /// held first responder while `@FocusState` reported nothing. So focus is
    /// *read* here, at the AppKit level, and `@FocusState` remains only for
    /// programmatically *setting* focus (the Find commands).
    var onSearchFieldFocusChange: (SearchField?) -> Void = { _ in }

    private var firstResponderObservation: NSKeyValueObservation?
    private var lastReportedField: SearchField?
    private var hasReportedField = false

    /// A focused `NSTextField`'s first responder is normally the window's
    /// field editor — an `NSTextView` whose delegate is the field itself. The
    /// field also holds first responder directly for an instant while its field
    /// editor is being installed; classify both, so the handoff between fields
    /// does not report a transient "no field focused".
    private static func searchField(forResponder responder: NSResponder?) -> SearchField? {
        let field: NSTextField?
        if let fieldEditor = responder as? NSTextView {
            field = fieldEditor.delegate as? NSTextField
        } else {
            field = responder as? NSTextField
        }
        switch field?.placeholderString {
        case ContentView.listSearchFieldPlaceholder: return .list
        case ContentView.detailSearchFieldPlaceholder: return .detail
        default: return nil
        }
    }

    private func reportFirstResponder(_ responder: NSResponder?) {
        let field = Self.searchField(forResponder: responder)
        guard !hasReportedField || field != lastReportedField else { return }
        hasReportedField = true
        lastReportedField = field
        onSearchFieldFocusChange(field)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation = nil
        guard let window else { return }
        // A window becoming key hands focus to its `initialFirstResponder`,
        // which defaults to the first field in the key-view loop — the file-list
        // search field. Launching the app, or just switching back to it, then
        // put the keyboard in the search box instead of leaving it where the
        // user left it. Pointing the initial responder at this inert sink means
        // there is nothing to steal focus in the first place.
        window.initialFirstResponder = self

        // First-responder changes happen on the main thread; the hop through
        // `DispatchQueue.main.async` coalesces reports that fire mid-event and
        // keeps the SwiftUI state mutation out of the KVO callback itself.
        firstResponderObservation = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            let responder = window.firstResponder
            DispatchQueue.main.async {
                self?.reportFirstResponder(responder)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        // Focus is parked here after a file is selected, so handle Delete /
        // Forward Delete to remove the selected document (Finder/Mail behavior)
        // since the file list itself is no longer first responder.
        let deleteKeyCodes: Set<UInt16> = [51, 117]
        if deleteKeyCodes.contains(event.keyCode) {
            onDelete()
            return
        }
        super.keyDown(with: event)
    }
}
#endif

#if DEBUG
#Preview("App - Loaded") {
    AppLoadedPreviewHost()
        .environmentObject(MarkdownAppCommandCenter())
        .environmentObject(FileOpenState())
        .frame(width: 393, height: 852)
}

#Preview("App - Empty") {
    ContentView(
        disablePersistenceRestore: true,
        disableLiveFileMonitoring: true
    )
        .environmentObject(MarkdownAppCommandCenter())
        .environmentObject(FileOpenState())
        .frame(width: 393, height: 852)
}

#Preview("Detail - Preview") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .preview, textSize: .large)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail - Source") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .source, textSize: .large)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail - Empty") {
    NavigationStack {
        DetailPreviewPane(file: nil, mode: .preview, textSize: .large)
            .navigationTitle("Markdown Preview")
    }
}

private struct AppLoadedPreviewHost: View {
    @State private var showsSource = true

    var body: some View {
        ContentView(
            previewFiles: [MarkdownPreviewFixtures.appLoadedFile],
            selectedPreviewFileID: MarkdownPreviewFixtures.appLoadedFile.url.standardizedFileURL.path,
            showsSourceInPreview: showsSource,
            disablePersistenceRestore: true,
            disableLiveFileMonitoring: true
        )
        .id(showsSource)
        .environmentObject(MarkdownAppCommandCenter())
        .task {
            guard showsSource else { return }
            try? await Task.sleep(for: .milliseconds(2000))
            showsSource = true
        }
    }
}
#endif
