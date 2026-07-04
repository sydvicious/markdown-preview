//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

/// Owns the shared search string and in-document search state plus all of the
/// search *data* logic (filtering, suggestions, match navigation, and the
/// selection bookkeeping that lets an active search take over — and later
/// restore — the detail selection). Keyboard focus stays in the View, since
/// `@FocusState` is inherently a View concern in SwiftUI.
@MainActor
final class SearchViewModel: ObservableObject {
    /// The single search string shared by the file-list and in-document search
    /// boxes. Both fields display it and both searches run off it.
    @Published var searchText = ""
    @Published private(set) var detailSearch = MarkdownSearchSession()
    /// Latest non-empty rendered-preview selection text, published from the
    /// preview web view so selection-driven find can use it.
    @Published var previewSelectedText: String?

    private let store: DocumentSessionStore
    private var didApplyDetailSearchSelection = false
    private var savedSelectionsBeforeDetailSearch: [String: [MarkdownSelectionRange]] = [:]
    #if os(macOS)
    private var lastFindPasteboardChangeCount: Int?
    #endif

    init(store: DocumentSessionStore) {
        self.store = store
    }

    // MARK: - Derived state

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSearchText: Bool {
        !trimmedSearchText.isEmpty
    }

    var resultCount: Int {
        detailSearch.resultCount
    }

    var detailSearchStatusText: String? {
        guard !detailSearch.query.isEmpty else { return nil }
        return detailSearch.resultPositionText ?? "0 results"
    }

    var listSearchSuggestions: [String] {
        store.listSearchSuggestions(prefix: searchText)
    }

    var detailSearchSuggestions: [String] {
        guard let currentDocument = store.currentDocument else { return [] }
        return store.detailSearchSuggestions(for: currentDocument.id, prefix: detailSearch.query)
    }

    func documentMatchesSearch(_ document: DocumentSessionStore.OpenedDocument) -> Bool {
        store.documentMatchesListSearch(document.id, query: trimmedSearchText)
    }

    /// Text to seed a find from the current selection: the rendered-preview
    /// selection when in preview mode, otherwise the source selection.
    func selectionSearchText(detailMode: ContentViewModel.DetailMode) -> String? {
        if detailMode == .preview {
            let normalizedPreviewSelection = previewSelectedText?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedPreviewSelection?.isEmpty == false {
                return normalizedPreviewSelection
            }
        }

        guard let currentDocument = store.currentDocument else { return nil }
        let selected = MarkdownSelectionClipboard.selectedMarkdown(
            in: currentDocument.file.contents,
            ranges: store.selections(for: currentDocument.id)
        )
        let normalized = selected?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    // MARK: - Mutating the search

    func setSearchText(_ query: String) {
        searchText = query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            SystemFindPasteboard.setQuery(trimmedQuery)
            #if os(macOS)
            // Remember our own write so it is not re-adopted as an external change.
            lastFindPasteboardChangeCount = SystemFindPasteboard.changeCount()
            #endif
        }
        updateDetailSearch(for: query)
    }

    func clearSearch() {
        setSearchText("")
    }

    func seedFromPasteboardIfEmpty() {
        guard trimmedSearchText.isEmpty,
              let existingQuery = SystemFindPasteboard.currentQuery(),
              !existingQuery.isEmpty else { return }
        setSearchText(existingQuery)
    }

    /// Runs the shared search for text chosen from a selection's "Search"
    /// edit-menu action. Focus is intentionally left to the caller.
    func searchForSelection(_ rawText: String) {
        let normalized = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        setSearchText(normalized)
    }

    #if os(macOS)
    func adoptSystemFindQueryIfChanged() {
        let changeCount = SystemFindPasteboard.changeCount()
        guard let lastChangeCount = lastFindPasteboardChangeCount else {
            // First observation only establishes a baseline; don't inherit a
            // stale find term from before the app started running.
            lastFindPasteboardChangeCount = changeCount
            return
        }
        guard changeCount != lastChangeCount else { return }
        lastFindPasteboardChangeCount = changeCount

        guard let query = SystemFindPasteboard.currentQuery(),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query != searchText else { return }
        setSearchText(query)
    }
    #endif

    func refreshDetailSearch() {
        if !detailSearch.query.isEmpty, let currentDocument = store.currentDocument,
           savedSelectionsBeforeDetailSearch[currentDocument.id] == nil {
            savedSelectionsBeforeDetailSearch[currentDocument.id] = store.selections(for: currentDocument.id)
        }
        detailSearch.refresh(in: store.currentDocument?.file.contents ?? "")
        applyDetailSearchSelection()
    }

    /// Moves to the next/previous match. Returns `false` when there is no active
    /// query, so the caller can decide to focus the search field instead.
    @discardableResult
    func moveToAdjacentMatch(_ direction: MarkdownSearchDirection) -> Bool {
        guard !detailSearch.query.isEmpty else { return false }
        _ = detailSearch.move(direction)
        applyDetailSearchSelection()
        return true
    }

    private func updateDetailSearch(for query: String) {
        let wasEmpty = detailSearch.query.isEmpty
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if wasEmpty, !trimmedQuery.isEmpty, let currentDocument = store.currentDocument {
            savedSelectionsBeforeDetailSearch[currentDocument.id] = store.selections(for: currentDocument.id)
        }

        detailSearch.updateQuery(query, in: store.currentDocument?.file.contents ?? "")
        applyDetailSearchSelection()
    }

    private func applyDetailSearchSelection() {
        guard let currentDocument = store.currentDocument else {
            didApplyDetailSearchSelection = false
            return
        }

        if !detailSearch.query.isEmpty {
            // While a search is active it owns the detail selection: highlight the
            // current match, or show no selection at all when nothing matches.
            let searchSelection = detailSearch.currentMatch.map { [$0] } ?? []
            if store.selections(for: currentDocument.id) != searchSelection {
                store.setSelections(searchSelection, for: currentDocument.id, text: currentDocument.file.contents)
            }
            didApplyDetailSearchSelection = true
            return
        }

        // The query is empty. Restore whatever selection existed before the
        // search took over the detail selection, if any.
        if didApplyDetailSearchSelection {
            let previousSelection = savedSelectionsBeforeDetailSearch.removeValue(forKey: currentDocument.id) ?? []
            store.setSelections(previousSelection, for: currentDocument.id, text: currentDocument.file.contents)
            didApplyDetailSearchSelection = false
        } else {
            savedSelectionsBeforeDetailSearch.removeValue(forKey: currentDocument.id)
        }
    }
}
