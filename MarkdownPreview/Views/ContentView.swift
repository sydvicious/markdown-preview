//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ContentView: View {
    private let disableLiveFileMonitoring: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var fileOpenState: FileOpenState
    @State private var isImporterPresented = false
    @StateObject private var viewModel: ContentViewModel

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
                    .toolbar {
                        #if !os(macOS)
                        ToolbarItem(placement: openButtonPlacement) {
                            Button {
                                isImporterPresented = true
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
                        ToolbarItemGroup(placement: viewButtonPlacement) {
                            #if os(macOS)
                            Button {
                                isImporterPresented = true
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
                                .keyboardShortcut("-", modifiers: [.command])
                                .accessibilityLabel("Decrease Text Size")
                                .accessibilityIdentifier("DecreaseTextSize")

                                Button {
                                    increaseTextSize(for: selectedDocumentID)
                                } label: {
                                    Image(systemName: "textformat.size.larger")
                                }
                                .disabled(!store.canIncreaseTextSize(for: selectedDocumentID))
                                .keyboardShortcut("=", modifiers: [.command, .shift])
                                .accessibilityLabel("Increase Text Size")
                                .accessibilityIdentifier("IncreaseTextSize")
                            }
                            #if os(macOS)
                            if store.selectedDocumentID != nil {
                                removeFromListButton
                            }
                            #endif
                        }
                    }
            }
        }
        .background(keyboardShortcutBridge)
        #if os(macOS)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: MarkdownFile.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleImport(result, isCompactWidth: isCompactWidth)
        }
        #else
        .sheet(isPresented: $isImporterPresented) {
            MarkdownDocumentPicker { url in
                viewModel.load(url: url, isCompactWidth: isCompactWidth)
                isImporterPresented = false
            } onCancel: {
                isImporterPresented = false
            }
        }
        #endif
        #if !os(macOS)
        .sheet(isPresented: $viewModel.isInitialOpenSheetPresented) {
            initialOpenSheet
        }
        #endif
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
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
                viewModel.acknowledgeMissingActiveDocument(isCompactWidth: isCompactWidth)
            }
        } message: { alert in
            Text("\"\(alert.fileName)\" is no longer available.")
        }
        .onChange(of: store.openedDocuments) { _, _ in
            viewModel.onDocumentsChanged()
            viewModel.presentInitialOpenSheetIfNeeded()
        }
        .onChange(of: store.selectedDocumentID) { _, _ in
            viewModel.onSelectionChanged()
        }
        .onChange(of: store.textSizesByDocumentID) { _, _ in
            store.persistTextSizes()
        }
        .onAppear {
            viewModel.restorePersistedDocumentsIfNeeded(isCompactWidth: isCompactWidth)
            viewModel.presentInitialOpenSheetIfNeeded()
            #if !os(macOS)
            if !disableLiveFileMonitoring {
                store.checkActiveDocumentForChanges(isCompactWidth: isCompactWidth)
                store.checkAllDocumentsForChanges(isCompactWidth: isCompactWidth)
            }
            #endif
        }
        #if !os(macOS)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            if !disableLiveFileMonitoring {
                store.checkActiveDocumentForChanges(isCompactWidth: isCompactWidth)
                store.checkAllDocumentsForChanges(isCompactWidth: isCompactWidth)
            }
        }
        #endif
        .onReceive(fileOpenState.$openedURL.compactMap { $0 }) { url in
            viewModel.load(url: url, isCompactWidth: isCompactWidth)
            fileOpenState.openedURL = nil
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if !disableLiveFileMonitoring {
                store.checkActiveDocumentForChanges(isCompactWidth: isCompactWidth)
            }
        }
        .onReceive(Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()) { _ in
            if !disableLiveFileMonitoring {
                store.checkAllDocumentsForChanges(isCompactWidth: isCompactWidth)
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            Group {
                if !store.didRestoreDocuments {
                    ProgressView("Loading Files")
                } else if store.sortedDocuments.isEmpty {
                    Text("No files loaded")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(selection: Binding(
                        get: { store.selectedDocumentID },
                        set: { store.selectedDocumentID = $0 }
                    )) {
                        #if os(macOS)
                        ForEach(store.groupedDocumentsByParentDirectory) { section in
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
                        #else
                        ForEach(store.sortedDocuments) { document in
                            sidebarDocumentRow(document)
                        }
                        .onDelete { offsets in
                            store.deleteDocuments(at: offsets, isCompactWidth: isCompactWidth)
                        }
                        #endif
                    }
                    #if os(macOS)
                    .onDeleteCommand(perform: removeSelectedDocumentFromList)
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
        .tag(document.id)
        .contextMenu {
            Button(role: .destructive) {
                removeDocumentFromList(id: document.id)
            } label: {
                Label("Remove from List", systemImage: "trash")
            }
        }
        #if !os(macOS)
        .swipeActions {
            Button(role: .destructive) {
                removeDocumentFromList(id: document.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        #endif
        #if os(macOS)
        .help(viewModel.tooltipPath(for: document.file.url))
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

                ZStack(alignment: .topLeading) {
                    previewPanel
                        .opacity(viewModel.detailMode == .preview ? 1 : 0)
                        .allowsHitTesting(viewModel.detailMode == .preview)
                        .accessibilityHidden(viewModel.detailMode != .preview)

                    sourcePanel
                        .opacity(viewModel.detailMode == .source ? 1 : 0)
                        .allowsHitTesting(viewModel.detailMode == .source)
                        .accessibilityHidden(viewModel.detailMode != .source)
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
                    isImporterPresented = true
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
                    )
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
                    )
                )
            }
        }
    }

    private var detailModePicker: some View {
        Picker("View", selection: $viewModel.detailMode) {
            Text("Preview").tag(ContentViewModel.DetailMode.preview)
            Text("Source").tag(ContentViewModel.DetailMode.source)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("View")
        .accessibilityIdentifier("DetailModePicker")
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
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

    private var removeFromListButton: some View {
        Button(role: .destructive) {
            removeSelectedDocumentFromList()
        } label: {
            Image(systemName: "trash")
        }
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
    private var keyboardShortcutBridge: some View {
        if let selectedDocumentID = store.selectedDocumentID {
            Button {
                increaseTextSize(for: selectedDocumentID)
            } label: {
                EmptyView()
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(!store.canIncreaseTextSize(for: selectedDocumentID))
            .accessibilityHidden(true)
            .opacity(0.001)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
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

    private func removeDocumentFromList(id: String) {
        let shouldShowSidebar = store.removeDocument(id: id, isCompactWidth: isCompactWidth)
        if shouldShowSidebar {
            viewModel.preferredCompactColumn = .sidebar
        }
    }

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSURL.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSURL.self) { item, _ in
            guard let url = item as? NSURL else { return }
            Task { @MainActor in
                viewModel.load(url: url as URL, isCompactWidth: isCompactWidth)
            }
        }
        return true
    }
    #endif

    private var store: DocumentSessionStore { viewModel.store }

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

#if DEBUG
#Preview("App - Loaded") {
    AppLoadedPreviewHost()
        .environmentObject(FileOpenState())
        .frame(width: 393, height: 852)
}

#Preview("App - Empty") {
    ContentView(
        disablePersistenceRestore: true,
        disableLiveFileMonitoring: true
    )
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
        .task {
            guard showsSource else { return }
            try? await Task.sleep(for: .milliseconds(2000))
            showsSource = true
        }
    }
}
#endif
