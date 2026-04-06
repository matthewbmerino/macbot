import XCTest
@testable import Macbot

final class AmbientSnapshotTests: XCTestCase {

    func testEmptySnapshotProducesEmptySummary() {
        let snap = AmbientSnapshot()
        // Default has empty app + idle 0 + battery -1 + online + memTotal 0
        XCTAssertEqual(snap.promptSummary, "")
    }

    func testActiveAppOnlyAppearsWithoutWindowTitle() {
        var snap = AmbientSnapshot()
        snap.frontmostApp = "Xcode"
        XCTAssertTrue(snap.promptSummary.contains("active: Xcode"))
        XCTAssertFalse(snap.promptSummary.contains("—"))
    }

    func testActiveAppWithWindowTitleIncludesIt() {
        var snap = AmbientSnapshot()
        snap.frontmostApp = "Xcode"
        snap.windowTitle = "MacbotApp.swift"
        XCTAssertTrue(snap.promptSummary.contains("Xcode — MacbotApp.swift"))
    }

    func testWindowTitleIsTruncated() {
        var snap = AmbientSnapshot()
        snap.frontmostApp = "Editor"
        snap.windowTitle = String(repeating: "x", count: 200)
        // Truncated to 80 chars; the joined summary should be substantially shorter than 200.
        XCTAssertLessThan(snap.promptSummary.count, 200)
    }

    func testIdleSecondsBelow60AreOmitted() {
        var snap = AmbientSnapshot()
        snap.frontmostApp = "Safari"
        snap.idleSeconds = 30
        XCTAssertFalse(snap.promptSummary.contains("idle"))
    }

    func testIdleAboveOneMinuteIsRendered() {
        var snap = AmbientSnapshot()
        snap.frontmostApp = "Safari"
        snap.idleSeconds = 180
        XCTAssertTrue(snap.promptSummary.contains("idle: 3m"))
    }

    func testBatteryAndChargingMarker() {
        var snap = AmbientSnapshot()
        snap.batteryPercent = 87
        snap.isCharging = true
        XCTAssertTrue(snap.promptSummary.contains("battery: 87%+"))

        snap.isCharging = false
        XCTAssertTrue(snap.promptSummary.contains("battery: 87%"))
        XCTAssertFalse(snap.promptSummary.contains("87%+"))
    }

    func testNoBatteryWhenUnknown() {
        var snap = AmbientSnapshot()
        snap.batteryPercent = -1
        XCTAssertFalse(snap.promptSummary.contains("battery"))
    }

    func testOfflineFlag() {
        var snap = AmbientSnapshot()
        snap.networkOnline = false
        XCTAssertTrue(snap.promptSummary.contains("offline"))
    }

    func testRamFormatting() {
        var snap = AmbientSnapshot()
        snap.memoryUsedGB = 6.234
        snap.memoryTotalGB = 18
        XCTAssertTrue(snap.promptSummary.contains("ram: 6.2/18GB"))
    }

    func testFullSummaryUsesDotSeparator() {
        var snap = AmbientSnapshot()
        snap.frontmostApp = "Xcode"
        snap.idleSeconds = 120
        snap.batteryPercent = 50
        XCTAssertTrue(snap.promptSummary.contains(" · "))
    }
}
