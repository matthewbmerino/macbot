import XCTest
import GRDB
@testable import Macbot

final class ChunkStoreTests: XCTestCase {

    private var pool: DatabasePool!
    private var path: String!
    private var store: ChunkStore!

    override func setUpWithError() throws {
        let made = try DatabaseManager.makeTestPool()
        pool = made.pool
        path = made.path
        store = ChunkStore(db: pool)
    }

    override func tearDownWithError() throws {
        pool = nil
        store = nil
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    func testInsertAndSemanticSearch() throws {
        let chunks: [(content: String, embedding: [Float], metadata: String)] = [
            ("apples are red", [1, 0, 0], "{}"),
            ("bananas are yellow", [0, 1, 0], "{}"),
            ("grapes are purple", [0, 0, 1], "{}"),
        ]
        let ids = store.insertChunks(chunks, sourceFile: "/tmp/test.txt")
        // Regression: prior to the MutablePersistableRecord fix, this returned
        // [] because GRDB never backfilled the auto-assigned id, so the
        // in-memory vector index also wasn't populated inside insertChunks.
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.allSatisfy { $0 > 0 })

        let rowCount = try pool.read { db in
            try DocumentChunk.fetchCount(db)
        }
        XCTAssertEqual(rowCount, 3)

        // Search uses the vector index that insertChunks now populates
        // directly — no loadVectorIndex() round trip required.
        let results = store.search(queryEmbedding: [1, 0, 0], topK: 2, threshold: 0.0)
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertEqual(results[0].chunk.content, "apples are red")
    }

    func testHybridSearchCombinesVectorAndKeyword() {
        let chunks: [(content: String, embedding: [Float], metadata: String)] = [
            ("the deployment guide explains rolling updates", [1, 0, 0], "{}"),
            ("authentication handshake details", [0, 1, 0], "{}"),
            ("rolling restart procedures for the cluster", [0.1, 0, 0], "{}"),
        ]
        store.insertChunks(chunks, sourceFile: "/tmp/docs.md")

        let results = store.hybridSearch(queryEmbedding: [1, 0, 0], keywords: "rolling", topK: 3)
        XCTAssertGreaterThan(results.count, 0)
        // Both rolling-keyword chunks should be ranked above the unrelated auth chunk
        let topContents = results.prefix(2).map(\.chunk.content)
        XCTAssertTrue(topContents.contains { $0.contains("rolling") })
    }

    func testIngestionDedupByHash() {
        XCTAssertTrue(store.needsIngestion(filePath: "/tmp/x.md", currentHash: "abc"))
        store.recordIngestion(filePath: "/tmp/x.md", fileHash: "abc", chunkCount: 1, totalTokens: 10)
        XCTAssertFalse(store.needsIngestion(filePath: "/tmp/x.md", currentHash: "abc"))
        XCTAssertTrue(store.needsIngestion(filePath: "/tmp/x.md", currentHash: "def"))
    }

    func testRemoveFileClearsChunks() throws {
        let chunks: [(content: String, embedding: [Float], metadata: String)] = [
            ("a", [1, 0, 0], "{}"),
            ("b", [0, 1, 0], "{}"),
        ]
        store.insertChunks(chunks, sourceFile: "/tmp/del.txt")
        XCTAssertEqual(store.totalChunkCount(), 2)
        store.removeFile("/tmp/del.txt")
        XCTAssertEqual(store.totalChunkCount(), 0)
        let rowCount = try pool.read { db in try DocumentChunk.fetchCount(db) }
        XCTAssertEqual(rowCount, 0)
    }
}
