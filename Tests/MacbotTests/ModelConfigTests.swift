import XCTest
@testable import Macbot

final class ModelConfigTests: XCTestCase {

    private let key = "com.macbot.modelConfig"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testDefaultsAreM3ProTuned() {
        let config = ModelConfig()
        XCTAssertEqual(config.general, "qwen3.5:9b")
        XCTAssertEqual(config.coder, "qwen3.5:9b")
        XCTAssertEqual(config.reasoner, "qwen3.5:9b")
        XCTAssertEqual(config.vision, "gemma4:e4b")
        XCTAssertEqual(config.embedding, "qwen3-embedding:0.6b")
    }

    func testModelForCategoryRoutesRagToGeneral() {
        let config = ModelConfig()
        XCTAssertEqual(config.model(for: .rag), config.general)
        XCTAssertEqual(config.model(for: .coder), config.coder)
        XCTAssertEqual(config.model(for: .vision), config.vision)
    }

    func testNumCtxFitsBudget() {
        let config = ModelConfig()
        // Vision uses smaller ctx (KV cache cost)
        XCTAssertEqual(config.numCtx[.vision], 8192)
        XCTAssertEqual(config.numCtx[.general], 16384)
    }

    func testAllModelsExcludesEmpty() {
        var config = ModelConfig()
        config.coder = ""
        XCTAssertFalse(config.allModels.contains(""))
    }

    func testDisabledRolesReportEmptyAssignments() {
        var config = ModelConfig()
        config.coder = ""
        config.vision = ""
        XCTAssertEqual(Set(config.disabledRoles), Set([.coder, .vision]))
    }

    func testMigrationRewritesOversizedCoderModel() throws {
        // Seed UserDefaults with an oversized model from the old defaults
        var legacy = ModelConfig()
        legacy.coder = "deepseek-r1:14b"
        legacy.reasoner = "qwen2.5:32b"
        let data = try JSONEncoder().encode(legacy)
        UserDefaults.standard.set(data, forKey: key)

        let loaded = ModelConfig.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.coder, "qwen3.5:9b")
        XCTAssertEqual(loaded?.reasoner, "qwen3.5:9b")
    }

    func testMigrationRewritesOldVisionModel() throws {
        var legacy = ModelConfig()
        legacy.vision = "qwen3-vl:8b"
        let data = try JSONEncoder().encode(legacy)
        UserDefaults.standard.set(data, forKey: key)

        let loaded = ModelConfig.load()
        XCTAssertEqual(loaded?.vision, "gemma4:e4b")
    }

    func testMigrationLeavesGoodModelsAlone() throws {
        let config = ModelConfig()  // already current
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: key)

        let loaded = ModelConfig.load()
        XCTAssertEqual(loaded?.coder, config.coder)
        XCTAssertEqual(loaded?.vision, config.vision)
    }

    func testLoadReturnsNilWhenAbsent() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNil(ModelConfig.load())
    }

    func testSaveRoundTrip() throws {
        var config = ModelConfig()
        config.general = "custom:model"
        config.save()

        let loaded = ModelConfig.load()
        XCTAssertEqual(loaded?.general, "custom:model")
    }
}
