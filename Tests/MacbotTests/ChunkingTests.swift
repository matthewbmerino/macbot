import XCTest
@testable import Macbot

final class ChunkingTests: XCTestCase {

    private func makeIngester() -> DocumentIngester {
        // ChunkStore would need a DB; chunk() doesn't touch storage so we
        // construct a minimal store backed by a temp pool just so init is happy.
        let (pool, _) = (try? DatabaseManager.makeTestPool()) ?? (try! DatabaseManager.makeTestPool())
        let store = ChunkStore(db: pool)
        return DocumentIngester(client: MockInferenceProvider(), chunkStore: store)
    }

    func testMarkdownChunkingSplitsByHeaders() {
        let md = """
        # Intro
        Some intro text.

        # Section A
        Body of A.

        # Section B
        Body of B.
        """
        let chunks = makeIngester().chunk(content: md, fileExtension: "md")
        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        let sections = chunks.map(\.section)
        XCTAssertTrue(sections.contains("Intro"))
        XCTAssertTrue(sections.contains("Section A"))
        XCTAssertTrue(sections.contains("Section B"))
    }

    func testPlainTextChunkingProducesNonEmptyChunks() {
        let text = String(repeating: "Lorem ipsum dolor sit amet. ", count: 200)
        let chunks = makeIngester().chunk(content: text, fileExtension: "txt")
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertFalse(chunk.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testCodeChunkingProducesChunks() {
        let code = """
        func a() { return 1 }
        func b() { return 2 }
        func c() { return 3 }
        """
        let chunks = makeIngester().chunk(content: code, fileExtension: "swift")
        XCTAssertFalse(chunks.isEmpty)
    }

    func testEmptyContentProducesNoChunks() {
        let chunks = makeIngester().chunk(content: "", fileExtension: "txt")
        XCTAssertTrue(chunks.isEmpty || chunks.allSatisfy { $0.content.isEmpty })
    }
}
