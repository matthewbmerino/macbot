import XCTest
@testable import Macbot

final class VectorIndexTests: XCTestCase {

    func testL2NormMatchesNaiveCalculation() {
        let v: [Float] = [3, 4, 0]
        XCTAssertEqual(VectorIndex.l2Norm(v), 5, accuracy: 1e-5)
    }

    func testL2NormZeroVector() {
        XCTAssertEqual(VectorIndex.l2Norm([0, 0, 0]), 0)
    }

    func testCosineSimilarityIdenticalVectors() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(VectorIndex.cosineSimilarity(v, v), 1.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(VectorIndex.cosineSimilarity(a, b), 0.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOppositeVectors() {
        let a: [Float] = [1, 1, 0]
        let b: [Float] = [-1, -1, 0]
        XCTAssertEqual(VectorIndex.cosineSimilarity(a, b), -1.0, accuracy: 1e-5)
    }

    func testInsertAndCount() {
        let idx = VectorIndex()
        XCTAssertEqual(idx.count, 0)
        idx.insert(id: 1, embedding: [1, 0, 0])
        idx.insert(id: 2, embedding: [0, 1, 0])
        XCTAssertEqual(idx.count, 2)
    }

    func testInsertRejectsZeroVector() {
        let idx = VectorIndex()
        idx.insert(id: 1, embedding: [0, 0, 0])
        XCTAssertEqual(idx.count, 0)
    }

    func testSearchRanksByCosineSimilarity() {
        let idx = VectorIndex()
        idx.insert(id: 1, embedding: [1, 0, 0])  // best match for [1,0,0]
        idx.insert(id: 2, embedding: [0, 1, 0])
        idx.insert(id: 3, embedding: [0.9, 0.1, 0])  // very close to [1,0,0]

        let results = idx.search(query: [1, 0, 0], topK: 3)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].id, 1)
        XCTAssertEqual(results[1].id, 3)
        XCTAssertEqual(results[2].id, 2)
        XCTAssertGreaterThan(results[0].similarity, results[1].similarity)
        XCTAssertGreaterThan(results[1].similarity, results[2].similarity)
    }

    func testSearchRespectsTopK() {
        let idx = VectorIndex()
        for i in 1...10 {
            idx.insert(id: Int64(i), embedding: [Float(i), 0, 0])
        }
        let results = idx.search(query: [1, 0, 0], topK: 3)
        XCTAssertEqual(results.count, 3)
    }

    func testSearchRespectsThreshold() {
        let idx = VectorIndex()
        idx.insert(id: 1, embedding: [1, 0, 0])
        idx.insert(id: 2, embedding: [0, 1, 0])  // orthogonal — sim = 0

        let results = idx.search(query: [1, 0, 0], topK: 5, threshold: 0.5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, 1)
    }

    func testSearchEmptyIndex() {
        let idx = VectorIndex()
        let results = idx.search(query: [1, 0, 0], topK: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchSkipsDimensionMismatch() {
        let idx = VectorIndex()
        idx.insert(id: 1, embedding: [1, 0, 0, 0])  // 4-dim, query is 3-dim
        idx.insert(id: 2, embedding: [1, 0, 0])
        let results = idx.search(query: [1, 0, 0], topK: 5)
        // dim-mismatch entries are skipped
        XCTAssertEqual(results.map(\.id), [2])
    }

    func testRemove() {
        let idx = VectorIndex()
        idx.insert(id: 1, embedding: [1, 0, 0])
        idx.insert(id: 2, embedding: [0, 1, 0])
        idx.remove(id: 1)
        XCTAssertEqual(idx.count, 1)
        let results = idx.search(query: [1, 0, 0], topK: 5)
        XCTAssertEqual(results.first?.id, 2)
    }

    func testClear() {
        let idx = VectorIndex()
        idx.insert(id: 1, embedding: [1, 0, 0])
        idx.insert(id: 2, embedding: [0, 1, 0])
        idx.clear()
        XCTAssertEqual(idx.count, 0)
    }

    func testInsertBatch() {
        let idx = VectorIndex()
        idx.insertBatch([(1, [1, 0, 0]), (2, [0, 1, 0]), (3, [0, 0, 0])])  // last is zero, skipped
        XCTAssertEqual(idx.count, 2)
    }
}
