import XCTest
@testable import LoopForge

final class GraphViewportFitPolicyTests: XCTestCase {
    func testThreeLevelGraphFitsNarrowTaskViewportWithoutBisectingNode() {
        let metrics = GraphViewportFitPolicy.resolve(
            viewportWidth: 752,
            levelCount: 3,
            preferredNodeWidth: 196,
            minimumNodeWidth: 160,
            preferredColumnGap: 72,
            minimumColumnGap: 24,
            fixedTerminalAndInsetWidth: 192
        )

        XCTAssertTrue(metrics.fitsViewport)
        XCTAssertEqual(metrics.canvasWidth, 752, accuracy: 0.001)
        XCTAssertEqual(metrics.nodeWidth, 170.666_666, accuracy: 0.001)
        XCTAssertEqual(metrics.columnGap, 24, accuracy: 0.001)
    }

    func testDeepGraphPagesOnlyAtWholeColumnBoundary() {
        let metrics = GraphViewportFitPolicy.resolve(
            viewportWidth: 752,
            levelCount: 5,
            preferredNodeWidth: 196,
            minimumNodeWidth: 160,
            preferredColumnGap: 72,
            minimumColumnGap: 24,
            fixedTerminalAndInsetWidth: 192
        )

        XCTAssertFalse(metrics.fitsViewport)
        XCTAssertEqual(metrics.nodeWidth, 170.666_666, accuracy: 0.001)
        XCTAssertEqual(metrics.columnGap, 24, accuracy: 0.001)
        XCTAssertEqual(metrics.columnsPerViewport, 3)
        XCTAssertEqual(metrics.pageCount, 2)
        XCTAssertEqual(metrics.canvasWidth, 1_504, accuracy: 0.001)
    }

    func testWideViewportCapsCardAndSpacingTokens() {
        let metrics = GraphViewportFitPolicy.resolve(
            viewportWidth: 1_200,
            levelCount: 3,
            preferredNodeWidth: 196,
            minimumNodeWidth: 160,
            preferredColumnGap: 72,
            minimumColumnGap: 24,
            fixedTerminalAndInsetWidth: 192
        )

        XCTAssertTrue(metrics.fitsViewport)
        XCTAssertEqual(metrics.nodeWidth, 196, accuracy: 0.001)
        XCTAssertEqual(metrics.columnGap, 72, accuracy: 0.001)
        XCTAssertEqual(metrics.columnsPerViewport, 3)
        XCTAssertEqual(metrics.pageCount, 1)
        XCTAssertEqual(metrics.canvasWidth, 1_200, accuracy: 0.001)
    }
}
