//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ContentView: View {
    private enum DetailMode {
        case preview
        case source
    }

    private struct OpenedDocument: Identifiable, Equatable {
        let id: String
        var file: MarkdownFile
        var lastOpened: Date
        var bookmarkData: Data
    }

    private struct PersistedDocument: Codable {
        let id: String
        let lastOpened: Date
        let bookmarkData: Data
    }

    private let persistedDocumentsKey = "openedMarkdownDocuments"
    private let persistedSelectionKey = "selectedMarkdownDocumentID"

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var fileOpenState: FileOpenState
    @State private var isImporterPresented = false
    @State private var openedDocuments: [OpenedDocument] = []
    @State private var selectedDocumentID: OpenedDocument.ID?
    @State private var detailMode: DetailMode = .preview
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var errorMessage: String?
    @State private var didRestoreDocuments = false
    @State private var isRestoringDocuments = true
    @State private var isInitialOpenSheetPresented = false
    @State private var hasPresentedInitialOpenSheet = false

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        showsSourceInPreview: Bool = false,
        disablePersistenceRestore: Bool = false
    ) {
        let now = Date()
        let opened = previewFiles.map {
            OpenedDocument(
                id: $0.url.standardizedFileURL.path,
                file: $0,
                lastOpened: now,
                bookmarkData: Data()
            )
        }
        let selectedID = selectedPreviewFileID ?? opened.first?.id

        _openedDocuments = State(initialValue: opened)
        _selectedDocumentID = State(initialValue: selectedID)
        _detailMode = State(initialValue: showsSourceInPreview ? .source : .preview)
        _isRestoringDocuments = State(initialValue: !disablePersistenceRestore)
        _didRestoreDocuments = State(initialValue: disablePersistenceRestore)
        _hasPresentedInitialOpenSheet = State(initialValue: disablePersistenceRestore)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
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
                    .navigationTitle(detailNavigationTitle)
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
                            if currentDocument != nil {
                                Button {
                                    detailMode = detailMode == .preview ? .source : .preview
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
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: MarkdownFile.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        #if !os(macOS)
        .sheet(isPresented: $isInitialOpenSheetPresented) {
            initialOpenSheet
        }
        #endif
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        #endif
        .alert("Unable to Open File", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onChange(of: openedDocuments) { _, _ in
            persistDocuments()
            presentInitialOpenSheetIfNeeded()
        }
        .onChange(of: selectedDocumentID) { _, _ in
            persistSelectedDocument()
        }
        .onChange(of: isRestoringDocuments) { _, _ in
            presentInitialOpenSheetIfNeeded()
        }
        .onAppear {
            restorePersistedDocumentsIfNeeded()
            presentInitialOpenSheetIfNeeded()
        }
        .onReceive(fileOpenState.$openedURL.compactMap { $0 }) { url in
            load(url: url)
            fileOpenState.openedURL = nil
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            Group {
                if isRestoringDocuments {
                    ProgressView("Loading Files")
                } else if sortedDocuments.isEmpty {
                    Text("No files loaded")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(selection: $selectedDocumentID) {
                        ForEach(sortedDocuments) { document in
                            HStack {
                                Text(document.file.fileName)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .tag(document.id)
                                #if os(macOS)
                                .help(tooltipPath(for: document.file.url))
                                #endif
                        }
                        .onDelete(perform: deleteDocuments)
                    }
                }
            }
        }
    }

    private var detailPanel: some View {
        guard currentDocument != nil else {
            return AnyView(
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        return AnyView(
            Group {
                switch detailMode {
                case .preview:
                    previewPanel
                case .source:
                    sourcePanel
                }
            }
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
                    isInitialOpenSheetPresented = false
                    isImporterPresented = true
                }
                Button("Not now", role: .cancel) {
                    isInitialOpenSheetPresented = false
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    #endif

    private var sourcePanel: some View {
        Group {
            if let file = currentDocument?.file {
                ScrollView {
                    Text(file.contents)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var previewPanel: some View {
        Group {
            if let file = currentDocument?.file {
                MarkdownBlocksView(source: file.contents)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func load(url: URL) {
        do {
            let bookmarkData = try makeBookmarkData(for: url)
            upsertDocument(try MarkdownFile.load(from: url), bookmarkData: bookmarkData)
            detailMode = .preview
            preferredCompactColumn = .sidebar
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertDocument(_ file: MarkdownFile, bookmarkData: Data) {
        let id = file.url.standardizedFileURL.path
        if let index = openedDocuments.firstIndex(where: { $0.id == id }) {
            openedDocuments[index].file = file
            openedDocuments[index].lastOpened = Date()
            openedDocuments[index].bookmarkData = bookmarkData
        } else {
            openedDocuments.append(.init(id: id, file: file, lastOpened: Date(), bookmarkData: bookmarkData))
        }
        if !isCompactWidth {
            selectedDocumentID = id
        }
    }

    private var sortedDocuments: [OpenedDocument] {
        openedDocuments.sorted { $0.lastOpened > $1.lastOpened }
    }

    private var currentDocument: OpenedDocument? {
        guard let selectedDocumentID else { return nil }
        return openedDocuments.first(where: { $0.id == selectedDocumentID })
    }

    private func deleteDocuments(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sortedDocuments[$0].id }
        openedDocuments.removeAll(where: { idsToDelete.contains($0.id) })
        if let selectedDocumentID, idsToDelete.contains(selectedDocumentID) {
            self.selectedDocumentID = sortedDocuments.first?.id
        }
    }

    private func restorePersistedDocumentsIfNeeded() {
        guard !didRestoreDocuments else { return }
        didRestoreDocuments = true

        let decoder = JSONDecoder()
        guard let data = UserDefaults.standard.data(forKey: persistedDocumentsKey),
              let persisted = try? decoder.decode([PersistedDocument].self, from: data) else {
            isRestoringDocuments = false
            return
        }

        var restored: [OpenedDocument] = []
        for entry in persisted.sorted(by: { $0.lastOpened > $1.lastOpened }) {
            guard let file = loadFromBookmarkData(entry.bookmarkData) else { continue }
            restored.append(
                .init(
                    id: entry.id,
                    file: file,
                    lastOpened: entry.lastOpened,
                    bookmarkData: entry.bookmarkData
                )
            )
        }

        openedDocuments = restored
        if isCompactWidth {
            selectedDocumentID = nil
        } else {
            if let persistedSelection = UserDefaults.standard.string(forKey: persistedSelectionKey),
               restored.contains(where: { $0.id == persistedSelection }) {
                selectedDocumentID = persistedSelection
            } else {
                selectedDocumentID = restored.first?.id
            }
        }
        isRestoringDocuments = false
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var detailNavigationTitle: String {
        guard let currentDocument else { return "" }
        #if os(macOS)
        return disambiguatedTitle(for: currentDocument)
        #else
        return currentDocument.file.fileName
        #endif
    }

    private func presentInitialOpenSheetIfNeeded() {
        #if os(macOS)
        return
        #else
        guard !hasPresentedInitialOpenSheet else { return }
        guard !isRestoringDocuments else { return }
        guard openedDocuments.isEmpty else { return }
        hasPresentedInitialOpenSheet = true
        isInitialOpenSheetPresented = true
        #endif
    }

    private func disambiguatedTitle(for document: OpenedDocument) -> String {
        let baseName = document.file.fileName
        let parentName = document.file.url.deletingLastPathComponent().lastPathComponent
        if parentName.isEmpty {
            return baseName
        }
        return "\(baseName) – \(parentName)"
    }

    private func tooltipPath(for url: URL) -> String {
        let fullPath = url.path
        let homePath = NSHomeDirectory()
        guard fullPath == homePath || fullPath.hasPrefix(homePath + "/") else {
            return fullPath
        }
        return "~" + fullPath.dropFirst(homePath.count)
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

    private func persistDocuments() {
        let encoder = JSONEncoder()
        let persisted = openedDocuments.map {
            PersistedDocument(id: $0.id, lastOpened: $0.lastOpened, bookmarkData: $0.bookmarkData)
        }
        guard let data = try? encoder.encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: persistedDocumentsKey)
    }

    private func persistSelectedDocument() {
        UserDefaults.standard.set(selectedDocumentID, forKey: persistedSelectionKey)
    }

    private func makeBookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        do {
            return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        #else
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private func loadFromBookmarkData(_ bookmarkData: Data) -> MarkdownFile? {
        var isStale = false
        do {
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try MarkdownFile.load(from: url)
        } catch {
            return nil
        }
    }

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                load(url: url)
            }
        }
        return true
    }
    #endif

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

private struct MarkdownBlocksView: View {
    let source: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(MarkdownBlockParser.parse(source), id: \.id) { block in
                    switch block.kind {
                    case .heading(let level, let text):
                        Text(inlineAttributed(text))
                            .font(headingFont(level: level))
                            .fontWeight(.semibold)
                    case .paragraph(let text):
                        Text(inlineAttributed(text))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    if let checked = item.checkbox {
                                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                                            .foregroundColor(checked ? Color.accentColor : Color.secondary)
                                    } else {
                                        Text("•")
                                            .font(.body)
                                    }
                                    Text(inlineAttributed(item.text))
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, CGFloat(item.indent) * 18)
                            }
                        }
                    case .orderedList(let items):
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(item.order ?? (index + 1)).")
                                        .monospacedDigit()
                                        .font(.body)
                                    Text(inlineAttributed(item.text))
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, CGFloat(item.indent) * 18)
                            }
                        }
                    case .blockquote(let text):
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 4)
                            Text(inlineAttributed(text))
                                .font(.body)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .rule:
                        Divider()
                    case .code(let code):
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .headline
        default: return .body
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list([MarkdownListItem])
        case orderedList([MarkdownListItem])
        case blockquote(String)
        case rule
        case code(String)
    }

    let id = UUID()
    let kind: Kind
}

private struct MarkdownListItem: Identifiable {
    let id = UUID()
    let text: String
    let indent: Int
    let checkbox: Bool?
    let order: Int?
}

private enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [MarkdownListItem] = []
        var orderedListItems: [MarkdownListItem] = []
        var quoteLines: [String] = []
        var code: [String] = []
        var inCodeFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.init(kind: .paragraph(paragraph.joined(separator: " "))))
            paragraph.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(.init(kind: .list(listItems)))
            listItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedListItems.isEmpty else { return }
            blocks.append(.init(kind: .orderedList(orderedListItems)))
            orderedListItems.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.init(kind: .blockquote(quoteLines.joined(separator: "\n"))))
            quoteLines.removeAll()
        }

        func flushAll() {
            flushParagraph()
            flushList()
            flushOrderedList()
            flushQuote()
        }

        for line in lines {
            if line.hasPrefix("```") {
                flushAll()
                if inCodeFence {
                    blocks.append(.init(kind: .code(code.joined(separator: "\n"))))
                    code.removeAll()
                }
                inCodeFence.toggle()
                continue
            }

            if inCodeFence {
                code.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushAll()
                continue
            }

            if let heading = parseHeading(line) {
                flushAll()
                blocks.append(.init(kind: .heading(level: heading.level, text: heading.text)))
                continue
            }

            if let item = parseListItem(line) {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                listItems.append(item)
                continue
            }

            if let item = parseOrderedListItem(line) {
                flushParagraph()
                flushList()
                flushQuote()
                orderedListItems.append(item)
                continue
            }

            if let quote = parseBlockquote(line) {
                flushParagraph()
                flushList()
                flushOrderedList()
                quoteLines.append(quote)
                continue
            }

            if parseRule(line) {
                flushAll()
                blocks.append(.init(kind: .rule))
                continue
            }

            flushList()
            flushOrderedList()
            flushQuote()
            paragraph.append(line.trimmingCharacters(in: .whitespaces))
        }

        flushAll()
        if !code.isEmpty {
            blocks.append(.init(kind: .code(code.joined(separator: "\n"))))
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func parseListItem(_ line: String) -> MarkdownListItem? {
        let indent = indentLevel(in: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        let first = trimmed.first
        guard first == "-" || first == "*" || first == "+" else { return nil }
        guard trimmed.dropFirst().first == " " else { return nil }
        let rawText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let (text, checkbox) = parseCheckbox(rawText)
        return MarkdownListItem(text: text, indent: indent, checkbox: checkbox, order: nil)
    }

    private static func parseOrderedListItem(_ line: String) -> MarkdownListItem? {
        let indent = indentLevel(in: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let number = trimmed[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        let rawText = String(afterDot.dropFirst()).trimmingCharacters(in: .whitespaces)
        let (text, checkbox) = parseCheckbox(rawText)
        return MarkdownListItem(
            text: text,
            indent: indent,
            checkbox: checkbox,
            order: Int(number)
        )
    }

    private static func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == ">" else { return nil }
        let remaining = trimmed.dropFirst()
        return String(remaining.first == " " ? remaining.dropFirst() : remaining)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func parseRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let chars = Array(trimmed)
        guard chars.count >= 3 else { return false }
        let allowed = chars.filter { $0 == "-" || $0 == "*" || $0 == "_" }
        return allowed.count == chars.count && Set(chars).count == 1
    }

    private static func indentLevel(in line: String) -> Int {
        var width = 0
        for ch in line {
            if ch == " " {
                width += 1
            } else if ch == "\t" {
                width += 4
            } else {
                break
            }
        }
        return max(0, width / 2)
    }

    private static func parseCheckbox(_ text: String) -> (String, Bool?) {
        if text.hasPrefix("[ ] ") {
            return (String(text.dropFirst(4)), false)
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return (String(text.dropFirst(4)), true)
        }
        return (text, nil)
    }
}

private enum ContentViewPreviewData {
    static let fullFile: MarkdownFile = {
        MarkdownFile(url: previewReadmeURL, contents: fullContents)
    }()

    static let excerptFile: MarkdownFile = {
        MarkdownFile(url: previewReadmeURL, contents: excerptContents)
    }()

    private static let fullContents: String = {
        let fallback = "# Markdown Preview\n\nPreview content file could not be loaded."
        guard let text = try? String(contentsOf: previewReadmeURL, encoding: .utf8) else {
            return fallback
        }
        return text
    }()

    private static let excerptContents: String = {
        let lines = fullContents.components(separatedBy: .newlines)
        return lines.prefix(120).joined(separator: "\n")
    }()

    private static var previewReadmeURL: URL {
        let swiftFileURL = URL(fileURLWithPath: #filePath)
        return swiftFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("README.md")
    }
}

private struct DetailPreviewPane: View {
    enum Mode {
        case preview
        case source
    }

    let file: MarkdownFile?
    let mode: Mode

    var body: some View {
        Group {
            if let file {
                switch mode {
                case .preview:
                    MarkdownBlocksView(source: file.contents)
                case .source:
                    ScrollView {
                        Text(file.contents)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Color.clear
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }
}

#Preview("App - Loaded") {
    ContentView(
        previewFiles: [ContentViewPreviewData.fullFile],
        selectedPreviewFileID: ContentViewPreviewData.fullFile.url.standardizedFileURL.path,
        disablePersistenceRestore: true
    )
    .environmentObject(FileOpenState())
}

#Preview("App - Empty") {
    ContentView(disablePersistenceRestore: true)
        .environmentObject(FileOpenState())
}

#Preview("Detail - Preview") {
    NavigationStack {
        DetailPreviewPane(file: ContentViewPreviewData.excerptFile, mode: .preview)
            .navigationTitle(ContentViewPreviewData.excerptFile.fileName)
    }
}

#Preview("Detail - Source") {
    NavigationStack {
        DetailPreviewPane(file: ContentViewPreviewData.excerptFile, mode: .source)
            .navigationTitle(ContentViewPreviewData.excerptFile.fileName)
    }
}

#Preview("Detail - Empty") {
    NavigationStack {
        DetailPreviewPane(file: nil, mode: .preview)
            .navigationTitle("Markdown Preview")
    }
}
