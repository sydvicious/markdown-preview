//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing

struct DocumentSearchIndexTests {

    @Test func documentSearchIndexMatchesAgainstStrippedText() async throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/example.md"),
            contents: "# **Alpha** [beta](https://example.com)"
        )
        let index = DocumentSearchIndex(documents: [file])
        let documentID = file.url.standardizedFileURL.path

        #expect(index.containsMatch(in: documentID, query: "Alpha"))
        #expect(index.containsMatch(in: documentID, query: "beta"))
        #expect(index.containsMatch(in: documentID, query: "example.md"))
        #expect(index.containsMatch(in: documentID, query: "https") == false)
    }

    @Test func documentSearchIndexMatchesSubstringsWithinWords() async throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/readme.md"),
            contents: "The repository includes unit/UI test targets."
        )
        let index = DocumentSearchIndex(documents: [file])
        let documentID = file.url.standardizedFileURL.path

        #expect(index.containsMatch(in: documentID, query: "repo"))
    }

    // Building the index from a list that names one file twice used to trap.
    // On the Mac the index is built in a child process, so that if it ever
    // traps again it fails this test and not the whole run. Exit tests are
    // macOS only; elsewhere a trap would take the run with it.
    @Test(.timeLimit(.minutes(1)))
    func aDocumentListedTwiceIsIndexedOnce() async {
        #if os(macOS)
        await #expect(processExitsWith: .success) {
            exit(DocumentSearchIndexTests.indexesADocumentListedTwice() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        #else
        #expect(Self.indexesADocumentListedTwice())
        #endif
    }

    private static func indexesADocumentListedTwice() -> Bool {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/example.md"), contents: "Alpha")
        let index = DocumentSearchIndex(documents: [file, file])
        return index.containsMatch(in: file.url.standardizedFileURL.path, query: "Alpha")
    }

    // MARK: - Suggestions across the list

    private static let notes = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/list/alpha-notes.md"),
        contents: "alphabet soup"
    )
    private static let beta = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/list/Beta.md"),
        contents: "An Alpaca, and a [link](https://example.com/alphanumeric)."
    )
    private static let zeta = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/list/zeta.md"),
        contents: "alpine ALPHABET"
    )

    /// An index of the three, handed over out of order.
    private func makeIndex() -> DocumentSearchIndex {
        DocumentSearchIndex(documents: [Self.zeta, Self.notes, Self.beta])
    }

    private static func id(_ file: MarkdownFile) -> String {
        file.url.standardizedFileURL.path
    }

    /// The list's search looks at file names as well as text, so both are
    /// offered. Documents are taken in the order the list shows them, by name,
    /// and within one its name comes before its text.
    @Test func suggestsFromFileNamesAndTextInTheOrderOfTheList() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "al") == ["alpha", "alphabet", "Alpaca", "alpine"])
    }

    @Test func suggestsTheWordsOfAFileName() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "ze") == ["zeta"])
        #expect(index.suggestedCompletions(prefix: "no") == ["notes"])
        #expect(index.suggestedCompletions(prefix: "be") == ["Beta"])
    }

    /// A word in two documents, or in a name and a text, is offered once.
    @Test func aWordInTwoDocumentsIsSuggestedOnce() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "alphab") == ["alphabet"])
    }

    @Test func suggestsNoMoreThanTheLimitAcrossDocuments() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "al", limit: 2) == ["alpha", "alphabet"])
        #expect(index.suggestedCompletions(prefix: "al", limit: 3) == ["alpha", "alphabet", "Alpaca"])
    }

    @Test func suggestsNothingAcrossTheListForFewerThanTwoCharacters() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "a").isEmpty)
        #expect(index.suggestedCompletions(prefix: " a ").isEmpty)
        #expect(index.suggestedCompletions(prefix: "").isEmpty)
    }

    @Test func theWordAlreadyTypedIsNotSuggestedAcrossTheList() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "alpine").isEmpty)
        #expect(index.suggestedCompletions(prefix: "ZETA").isEmpty)
    }

    @Test func capitalsAndAccentsDoNotMatterAcrossTheList() async throws {
        let cafe = MarkdownFile(url: URL(fileURLWithPath: "/tmp/list/Café.md"), contents: "The CAFETERIA")
        let index = DocumentSearchIndex(documents: [cafe])

        #expect(index.suggestedCompletions(prefix: "caf") == ["Café", "CAFETERIA"])
        #expect(index.suggestedCompletions(prefix: "CAFET") == ["CAFETERIA"])
    }

    /// A link's address is not text the reader sees, in the list as in a
    /// document.
    @Test func aLinksAddressIsNotSuggestedAcrossTheList() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(prefix: "alphan").isEmpty)
        #expect(index.suggestedCompletions(prefix: "ht").isEmpty)
    }

    // MARK: - Suggestions from one document in the index

    /// Searching inside a document looks at its text and not its name.
    @Test func suggestsFromOneDocumentsTextAndNotItsName() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(in: Self.id(Self.zeta), prefix: "al") == ["alpine", "ALPHABET"])
        #expect(index.suggestedCompletions(in: Self.id(Self.zeta), prefix: "ze").isEmpty)
        #expect(index.suggestedCompletions(in: Self.id(Self.notes), prefix: "al") == ["alphabet"])
    }

    @Test func suggestsNothingFromADocumentThatIsNotInTheIndex() async throws {
        let index = makeIndex()

        #expect(index.suggestedCompletions(in: "/tmp/list/never-opened.md", prefix: "al").isEmpty)
    }

    @Test func suggestionsFollowTheDocumentsInTheIndex() async throws {
        let index = makeIndex()

        index.remove(documentID: Self.id(Self.zeta))
        #expect(index.suggestedCompletions(prefix: "al") == ["alpha", "alphabet", "Alpaca"])
        #expect(index.suggestedCompletions(prefix: "ze").isEmpty)

        index.upsert(MarkdownFile(url: Self.notes.url, contents: "almond"))
        #expect(index.suggestedCompletions(prefix: "al") == ["alpha", "almond", "Alpaca"])
        #expect(index.suggestedCompletions(in: Self.id(Self.notes), prefix: "al") == ["almond"])
    }

    // MARK: - Reading a document's text, off the path of an open

    /// Stands in for the thread the index has text read on. It keeps what it
    /// was asked to read, and the test hands back what it likes, when it likes.
    private final class HeldBuilds {
        typealias Deliver = @MainActor @Sendable (MarkdownTextOffsetMapping) -> Void
        private(set) var asked: [(contents: String, deliver: Deliver)] = []

        var build: DocumentSearchIndex.BackgroundBuild {
            { [self] contents, deliver in asked.append((contents, deliver)) }
        }
    }

    /// Reading a document's text for searching is as much work as showing it,
    /// and opening it does not wait for that.
    @Test func addingADocumentAsksForItsTextToBeReadAndDoesNotReadIt() {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)

        index.upsert(Self.notes)

        #expect(index.hasReadText(of: Self.id(Self.notes)) == false)
        #expect(held.asked.map(\.contents) == [Self.notes.contents])
    }

    /// As at launch, when every listed document goes in at once.
    @Test func anIndexMadeFromAListAsksForEachDocumentToBeRead() {
        let held = HeldBuilds()
        let files = [Self.zeta, Self.notes, Self.beta]
        let index = DocumentSearchIndex(documents: files, backgroundBuild: held.build)

        #expect(Set(held.asked.map(\.contents)) == Set(files.map(\.contents)))
        #expect(files.allSatisfy { !index.hasReadText(of: Self.id($0)) })
    }

    @Test func aSearchThatComesBeforeTheTextHasBeenReadReadsIt() {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)

        #expect(index.containsMatch(in: Self.id(Self.notes), query: "soup"))
        #expect(index.hasReadText(of: Self.id(Self.notes)))
    }

    @Test func aSearchTheFileNameAnswersDoesNotReadTheText() {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)

        #expect(index.containsMatch(in: Self.id(Self.notes), query: "notes"))
        #expect(index.hasReadText(of: Self.id(Self.notes)) == false)
    }

    @MainActor
    @Test func textReadInTheBackgroundIsWhatASearchUses() throws {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)
        let read = MarkdownTextOffsetMapping(sourceText: Self.notes.contents)

        try #require(held.asked.first).deliver(read)

        #expect(index.hasReadText(of: Self.id(Self.notes)))
        #expect(index.entry(for: Self.id(Self.notes))?.mapping === read)
    }

    /// The document changed on disk while its old text was being read.
    @MainActor
    @Test func textReadForADocumentThatHasSinceChangedIsDropped() throws {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)
        index.upsert(MarkdownFile(url: Self.notes.url, contents: "almond"))

        try #require(held.asked.first).deliver(MarkdownTextOffsetMapping(sourceText: Self.notes.contents))

        #expect(index.hasReadText(of: Self.id(Self.notes)) == false)
        #expect(index.containsMatch(in: Self.id(Self.notes), query: "almond"))
        #expect(index.containsMatch(in: Self.id(Self.notes), query: "soup") == false)
    }

    @MainActor
    @Test func textReadForADocumentNoLongerInTheIndexIsDropped() throws {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)
        index.remove(documentID: Self.id(Self.notes))

        try #require(held.asked.first).deliver(MarkdownTextOffsetMapping(sourceText: Self.notes.contents))

        #expect(index.entry(for: Self.id(Self.notes)) == nil)
        #expect(index.hasReadText(of: Self.id(Self.notes)) == false)
    }

    /// A search got there first and read the text itself. What it read stays.
    @MainActor
    @Test func textReadInTheBackgroundAfterASearchReadItChangesNothing() throws {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)
        let readByTheSearch = try #require(index.entry(for: Self.id(Self.notes))?.mapping)

        try #require(held.asked.first).deliver(MarkdownTextOffsetMapping(sourceText: Self.notes.contents))

        #expect(index.entry(for: Self.id(Self.notes))?.mapping === readByTheSearch)
    }

    /// A document that is already listed is opened again, with nothing in it
    /// changed.
    @MainActor
    @Test func addingADocumentAgainWithTheSameTextKeepsWhatWasRead() throws {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)
        let read = MarkdownTextOffsetMapping(sourceText: Self.notes.contents)
        try #require(held.asked.first).deliver(read)

        index.upsert(Self.notes)

        #expect(index.entry(for: Self.id(Self.notes))?.mapping === read)
        #expect(held.asked.count == 1)
    }

    /// And again before its text has been read: the one reading under way is
    /// enough.
    @MainActor
    @Test func addingADocumentAgainWhileItsTextIsBeingReadAsksForNothingMore() throws {
        let held = HeldBuilds()
        let index = DocumentSearchIndex(backgroundBuild: held.build)
        index.upsert(Self.notes)

        index.upsert(Self.notes)

        #expect(held.asked.count == 1)
        try #require(held.asked.first).deliver(MarkdownTextOffsetMapping(sourceText: Self.notes.contents))
        #expect(index.hasReadText(of: Self.id(Self.notes)))
    }

    /// With nowhere else to read it, the text is read when a search needs it.
    @Test func withNoBackgroundToReadInTheTextIsReadWhenASearchNeedsIt() {
        let index = DocumentSearchIndex(documents: [Self.notes])

        #expect(index.hasReadText(of: Self.id(Self.notes)) == false)
        #expect(index.containsMatch(in: Self.id(Self.notes), query: "soup"))
        #expect(index.hasReadText(of: Self.id(Self.notes)))
    }
}
