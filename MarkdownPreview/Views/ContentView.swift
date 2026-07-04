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

private enum SearchField: Hashable {
    case list
    case detail
}

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
    #if os(macOS)
    @State private var macFirstResponderSink = MacFirstResponderSink()
    #endif

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
                    .modifier(SidebarTitleOnIPhone(isActive: usesSingleColumnNavigation))
                    .toolbar {
                        #if os(macOS)
                        // Give the file list its own remove control next to the
                        // list, so removal is discoverable without hunting through
                        // the detail toolbar or the row context menu. Always
                        // present (disabled when nothing is selected) so it does
                        // not pop in and out of the toolbar.
                        ToolbarItem(placement: .automatic) {
                            removeFromListButton
                        }
                        #else
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
                        #endif
                    }
            }
        } detail: {
            NavigationStack {
                detailPanel
                    .navigationTitle(viewModel.detailNavigationTitle())
                    .modifier(InlineTitleOnIOS())
                    .toolbar {
                        if store.currentDocument != nil, showsToolbarDetailSearch {
                            ToolbarItem(placement: detailSearchToolbarPlacement) {
                                detailSearchToolbarItem
                            }
                        }
                        ToolbarItemGroup(placement: viewButtonPlacement) {
                            #if os(macOS)
                            Button {
                                viewModel.isImporterPresented = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Open")
                            .accessibilityIdentifier("Open")
                            #endif
                            if let selectedDocumentID = store.selectedDocumentID {
                                Button {
                                    decreaseTextSize(for: selectedDocumentID)
                                } label: {
                                    Image(systemName: "textformat.size.smaller")
                                }
                                .disabled(!store.canDecreaseTextSize(for: selectedDocumentID))
                                .accessibilityLabel("Decrease Text Size")
                                .accessibilityIdentifier("DecreaseTextSize")

                                Button {
                                    increaseTextSize(for: selectedDocumentID)
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
        .onExitCommand(perform: cancelFocusedSearch)
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
            clearMacDefaultSearchFocusIfNeeded()
            syncCommandCenter()
        }
        .onChange(of: store.selectedDocumentID) { _, _ in
            previewSelectedText = nil
            viewModel.onSelectionChanged()
            refreshDetailSearch()
            clearMacDefaultSearchFocusIfNeeded()
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
        .onChange(of: focusedSearchField) { _, _ in
            syncCommandCenter()
        }
        .onAppear {
            viewModel.restorePersistedDocumentsIfNeeded(isCompactWidth: usesSingleColumnNavigation)
            refreshDetailSearch()
            presentInitialOpenPromptIfNeeded()
            clearMacDefaultSearchFocusIfNeeded()
            syncCommandCenter()
            #if os(macOS)
            adoptSystemFindQueryIfChanged()
            #else
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
        #if os(macOS)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            adoptSystemFindQueryIfChanged()
        }
        #else
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
                } else if isListSearchFiltering, filteredDocumentsCount == 0 {
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
                        ForEach(filteredGroupedDocumentsByParentDirectory) { section in
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
                    .onDeleteCommand(perform: removeSelectedDocumentFromList)
                    .contextMenu(forSelectionType: DocumentSessionStore.OpenedDocument.ID.self) { ids in
                        Button(role: .destructive) {
                            ids.forEach { removeDocumentFromList(id: $0) }
                        } label: {
                            Label("Remove from List", systemImage: "trash")
                        }
                    }
                    #else
                    List {
                        ForEach(filteredSortedDocuments) { document in
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
        }
    }

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
            Button(role: .destructive) {
                removeDocumentFromList(id: document.id)
            } label: {
                Label("Remove from List", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                removeDocumentFromList(id: document.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
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

    private var showsToolbarDetailSearch: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom != .phone
        #endif
    }

    private var usesSingleColumnNavigation: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && isCompactWidth
        #else
        false
        #endif
    }

    private var openButtonPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

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

    private var removeFromListButton: some View {
        Button(role: .destructive) {
            removeSelectedDocumentFromList()
        } label: {
            Image(systemName: "trash")
        }
        .disabled(store.selectedDocumentID == nil)
        .accessibilityLabel("Remove from List")
        .accessibilityIdentifier("RemoveFromList")
    }

    private var removeButtonPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    @ViewBuilder
    private var macFirstResponderSinkBackground: some View {
        #if os(macOS)
        MacFirstResponderSinkView(
            sink: macFirstResponderSink,
            onDelete: removeSelectedDocumentFromList
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        #endif
    }

    private func removeSelectedDocumentFromList() {
        guard let selectedDocumentID = store.selectedDocumentID else { return }
        removeDocumentFromList(id: selectedDocumentID)
    }

    private func increaseTextSize(for documentID: String) {
        store.increaseTextSize(for: documentID)
    }

    private func decreaseTextSize(for documentID: String) {
        store.decreaseTextSize(for: documentID)
    }

    private func syncCommandCenter() {
        let canIncreaseTextSize = store.selectedDocumentID.map(store.canIncreaseTextSize(for:)) ?? false
        let canDecreaseTextSize = store.selectedDocumentID.map(store.canDecreaseTextSize(for:)) ?? false
        commandCenter.update(
            canFind: canHandleFindCommand,
            handleFind: handleFindCommand,
            canProjectFind: !store.openedDocuments.isEmpty,
            handleProjectFind: focusListSearch,
            canUseSelectionForFind: currentSelectionSearchText != nil,
            handleUseSelectionForFind: useCurrentSelectionForFind,
            canFindNext: detailSearch.resultCount > 0,
            handleFindNext: { navigateDetailSearch(.forward) },
            canFindPrevious: detailSearch.resultCount > 0,
            handleFindPrevious: { navigateDetailSearch(.backward) },
            canIncreaseTextSize: canIncreaseTextSize,
            handleIncreaseTextSize: {
                guard let selectedDocumentID = store.selectedDocumentID else { return }
                increaseTextSize(for: selectedDocumentID)
            },
            canDecreaseTextSize: canDecreaseTextSize,
            handleDecreaseTextSize: {
                guard let selectedDocumentID = store.selectedDocumentID else { return }
                decreaseTextSize(for: selectedDocumentID)
            },
            handleCancelSearch: cancelFocusedSearch,
            canRemoveFromList: store.selectedDocumentID != nil,
            handleRemoveFromList: removeSelectedDocumentFromList
        )
    }

    private var listSearchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search files", text: searchBinding)
                    .searchFieldTextInputBehavior()
                    .focused($focusedSearchField, equals: .list)
                    .accessibilityIdentifier("ListSearchField")

                Button {
                    clearSearch()
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

            if focusedSearchField == .list, !listSearchSuggestions.isEmpty {
                searchSuggestionsRow(listSearchSuggestions) { suggestion in
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

            if focusedSearchField == .detail, !detailSearchSuggestions.isEmpty {
                searchSuggestionsRow(detailSearchSuggestions) { suggestion in
                    setSearchText(suggestion, focus: .detail)
                }
            }
        }
    }

    private var detailSearchToolbarItem: some View {
        HStack(spacing: 8) {
            detailSearchField(compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            detailSearchStatusLabel
                .fixedSize()
            detailSearchNavigationButtons
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailSearchField(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search in file", text: searchBinding)
                .searchFieldTextInputBehavior()
                .focused($focusedSearchField, equals: .detail)
                .onSubmit {
                    navigateDetailSearch(.forward)
                }
                .accessibilityIdentifier("DetailSearchField")

            Button {
                clearSearch()
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
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        .background(searchFieldBackground)
        .modifier(CompactControlSize(isCompact: compact))
        .layoutPriority(compact ? 1 : 0)
    }

    private var detailSearchStatusLabel: some View {
        Text(detailSearchStatusText ?? "0 results")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, alignment: .trailing)
    }

    private var detailSearchNavigationButtons: some View {
        HStack(spacing: 6) {
            Button {
                navigateDetailSearch(.backward)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(detailSearch.resultCount == 0)
            .accessibilityLabel("Previous Result")

            Button {
                navigateDetailSearch(.forward)
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

    private func removeDocumentFromList(id: String) {
        let shouldShowSidebar = store.removeDocument(id: id, isCompactWidth: usesSingleColumnNavigation)
        if shouldShowSidebar {
            viewModel.preferredCompactColumn = .sidebar
        }
        // Keep the shared search string intact (the file list stays filtered);
        // just re-run the in-document search against whatever is now current.
        refreshDetailSearch()
    }

    private func presentInitialOpenPromptIfNeeded() {
        #if os(macOS)
        viewModel.scheduleStartupImporterIfNeeded()
        #else
        _ = viewModel.presentInitialOpenPromptIfNeeded()
        #endif
    }

    #if os(macOS)
    private func clearMacDefaultSearchFocusIfNeeded() {
        guard focusedSearchField == nil, !viewModel.isImporterPresented else { return }

        Task { @MainActor in
            let delays: [UInt64] = [0, 50_000_000, 150_000_000]
            for delay in delays {
                if delay == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard focusedSearchField == nil, !viewModel.isImporterPresented else { return }
                focusedSearchField = nil
                macFirstResponderSink.focus()
            }
        }
    }
    #else
    private func clearMacDefaultSearchFocusIfNeeded() {}
    #endif

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

    private var hasSearchText: Bool {
        search.hasSearchText
    }

    private var isListSearchFiltering: Bool {
        hasSearchText && isSearchHostAppActive
    }

    private var isSearchHostAppActive: Bool {
        guard scenePhase == .active else { return false }
        #if os(macOS)
        return NSApp.isActive
        #else
        return true
        #endif
    }

    private var filteredSortedDocuments: [DocumentSessionStore.OpenedDocument] {
        guard isListSearchFiltering else { return store.sortedDocuments }
        return store.sortedDocuments.filter(matchesListSearch)
    }

    private var filteredGroupedDocumentsByParentDirectory: [DocumentSessionStore.DocumentSection] {
        guard isListSearchFiltering else { return store.groupedDocumentsByParentDirectory }

        return store.groupedDocumentsByParentDirectory.compactMap { section in
            let documents = section.documents.filter(matchesListSearch)
            guard !documents.isEmpty else { return nil }
            return DocumentSessionStore.DocumentSection(
                directoryPath: section.directoryPath,
                label: section.label,
                documents: documents
            )
        }
    }

    private var filteredDocumentsCount: Int {
        filteredSortedDocuments.count
    }

    private var detailSearchStatusText: String? {
        guard !detailSearch.query.isEmpty else { return nil }
        return detailSearch.resultPositionText ?? "0 results"
    }

    private var listSearchSuggestions: [String] {
        store.listSearchSuggestions(prefix: searchText)
    }

    private var detailSearchSuggestions: [String] {
        guard let currentDocument = store.currentDocument else { return [] }
        return store.detailSearchSuggestions(for: currentDocument.id, prefix: detailSearch.query)
    }

    private var currentSelectionSearchText: String? {
        search.selectionSearchText(detailMode: viewModel.detailMode)
    }

    private var canHandleFindCommand: Bool {
        if usesSingleColumnNavigation {
            if viewModel.preferredCompactColumn == .detail {
                return store.currentDocument != nil
            }
            return !store.openedDocuments.isEmpty
        }

        if store.currentDocument != nil {
            return true
        }

        return !store.openedDocuments.isEmpty
    }

    private func matchesListSearch(_ document: DocumentSessionStore.OpenedDocument) -> Bool {
        search.documentMatchesSearch(document)
    }

    private func deleteFilteredDocuments(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { filteredSortedDocuments[safe: $0]?.id }
        idsToDelete.forEach { removeDocumentFromList(id: $0) }
    }

    private func setSearchText(_ query: String, focus: SearchField? = nil) {
        search.setSearchText(query)
        if let focus {
            focusedSearchField = focus
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

    private func clearSearch() {
        pendingSearchFocusTask?.cancel()
        setSearchText("")
        focusedSearchField = nil
    }

    private func seedSearchFromPasteboardIfEmpty() {
        search.seedFromPasteboardIfEmpty()
    }

    private func focusListSearch() {
        if usesSingleColumnNavigation {
            viewModel.preferredCompactColumn = .sidebar
        }
        seedSearchFromPasteboardIfEmpty()
        requestSearchFocus(.list)
    }

    private func focusDetailSearch() {
        guard store.currentDocument != nil else { return }
        if usesSingleColumnNavigation {
            viewModel.preferredCompactColumn = .detail
        }
        seedSearchFromPasteboardIfEmpty()
        requestSearchFocus(.detail)
    }

    private func requestSearchFocus(_ field: SearchField) {
        pendingSearchFocusTask?.cancel()
        focusedSearchField = field

        #if os(macOS)
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

    private func handleFindCommand() {
        if usesSingleColumnNavigation {
            if viewModel.preferredCompactColumn == .detail, store.currentDocument != nil {
                focusDetailSearch()
            } else if !store.openedDocuments.isEmpty {
                focusListSearch()
            }
            return
        }

        if store.currentDocument != nil {
            focusDetailSearch()
        } else if !store.openedDocuments.isEmpty {
            focusListSearch()
        }
    }

    private func navigateDetailSearch(_ direction: MarkdownSearchDirection) {
        if !search.moveToAdjacentMatch(direction) {
            focusDetailSearch()
        }
    }

    private func useCurrentSelectionForFind() {
        guard let currentSelectionSearchText else { return }
        setSearchText(currentSelectionSearchText, focus: .detail)
    }

    /// Runs the shared search for text chosen from a selection's "Search" edit-menu
    /// action. Does not steal keyboard focus, so the highlighted match stays visible
    /// instead of being covered by the on-screen keyboard.
    private func searchForSelection(_ rawText: String) {
        search.searchForSelection(rawText)
    }

    private func cancelFocusedSearch() {
        guard !searchText.isEmpty else { return }
        clearSearch()
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

private struct SidebarTitleOnIPhone: ViewModifier {
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
private final class MacFirstResponderSink {
    weak var view: NSView?

    func focus() {
        guard let view else { return }
        let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        window?.makeFirstResponder(view)
    }
}

private struct MacFirstResponderSinkView: NSViewRepresentable {
    let sink: MacFirstResponderSink
    var onDelete: () -> Void = {}

    func makeNSView(context: Context) -> MacFirstResponderSinkNSView {
        let view = MacFirstResponderSinkNSView(frame: .zero)
        view.setAccessibilityElement(false)
        view.onDelete = onDelete
        sink.view = view
        return view
    }

    func updateNSView(_ nsView: MacFirstResponderSinkNSView, context: Context) {
        nsView.onDelete = onDelete
        sink.view = nsView
    }
}

private final class MacFirstResponderSinkNSView: NSView {
    var onDelete: () -> Void = {}
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

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
