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
                    #if !os(macOS)
                    .toolbar {
                        ToolbarItem(placement: openButtonPlacement) {
                            Button {
                                isImporterPresented = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Open")
                            .accessibilityIdentifier("Open")
                        }
                    }
                    #endif
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
                            if store.currentDocument != nil {
                                Button {
                                    viewModel.toggleDetailMode()
                                } label: {
                                    Image(systemName: "rectangle.2.swap")
                                }
                                .accessibilityLabel("View")
                                .accessibilityIdentifier("View")
                            }
                        }
                    }
            }
        }
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
                        ForEach(store.sortedDocuments) { document in
                            HStack {
                                Text(document.file.fileName)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .tag(document.id)
                                #if os(macOS)
                                .help(viewModel.tooltipPath(for: document.file.url))
                                #endif
                        }
                        .onDelete { offsets in
                            store.deleteDocuments(at: offsets, isCompactWidth: isCompactWidth)
                        }
                    }
                }
            }
        }
    }

    private var detailPanel: some View {
        guard store.currentDocument != nil else {
            return AnyView(
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        return AnyView(
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
                    selections: Binding(
                        get: { store.selections(for: document.id) },
                        set: { store.setSelections($0, for: document.id, text: document.file.contents) }
                    )
                )
            }
        }
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

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                viewModel.load(url: url, isCompactWidth: isCompactWidth)
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

#Preview("App - Loaded") {
    ContentView(
        previewFiles: [MarkdownPreviewFixtures.fullFile],
        selectedPreviewFileID: MarkdownPreviewFixtures.fullFile.url.standardizedFileURL.path,
        disablePersistenceRestore: true,
        disableLiveFileMonitoring: true
    )
    .environmentObject(FileOpenState())
}

#Preview("App - Empty") {
    ContentView(
        disablePersistenceRestore: true,
        disableLiveFileMonitoring: true
    )
        .environmentObject(FileOpenState())
}

#Preview("Detail - Preview") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .preview)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail - Source") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .source)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail - Empty") {
    NavigationStack {
        DetailPreviewPane(file: nil, mode: .preview)
            .navigationTitle("Markdown Preview")
    }
}
