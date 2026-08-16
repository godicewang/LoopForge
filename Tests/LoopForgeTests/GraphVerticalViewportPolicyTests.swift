import XCTest
@testable import LoopForge

final class GraphVerticalViewportPolicyTests: XCTestCase {
    func testCompactGraphShowsOneWholeRowAndExplicitContinuation() {
        let metrics = GraphVerticalViewportPolicy.resolve(
            maximumRows: 4,
            nodeHeight: 108,
            rowGap: 24,
            expanded: false
        )

        XCTAssertEqual(metrics.rowsPerViewport, 1)
        XCTAssertEqual(metrics.pageCount, 4)
        XCTAssertEqual(metrics.viewportHeight, 152, accuracy: 0.001)
        XCTAssertEqual(metrics.canvasHeight, 548, accuracy: 0.001)
        XCTAssertTrue(metrics.hasContinuation)
    }

    func testSingleRowCompactGraphNeedsNoContinuation() {
        let metrics = GraphVerticalViewportPolicy.resolve(
            maximumRows: 1,
            nodeHeight: 108,
            rowGap: 24,
            expanded: false
        )

        XCTAssertEqual(metrics.rowsPerViewport, 1)
        XCTAssertEqual(metrics.pageCount, 1)
        XCTAssertEqual(metrics.viewportHeight, 152, accuracy: 0.001)
        XCTAssertEqual(metrics.canvasHeight, 152, accuracy: 0.001)
        XCTAssertFalse(metrics.hasContinuation)
    }

    func testExpandedGraphShowsEveryWholeRow() {
        let metrics = GraphVerticalViewportPolicy.resolve(
            maximumRows: 4,
            nodeHeight: 132,
            rowGap: 32,
            expanded: true
        )

        XCTAssertEqual(metrics.rowsPerViewport, 4)
        XCTAssertEqual(metrics.pageCount, 1)
        XCTAssertEqual(metrics.viewportHeight, 676, accuracy: 0.001)
        XCTAssertEqual(metrics.canvasHeight, 676, accuracy: 0.001)
        XCTAssertFalse(metrics.hasContinuation)
    }
}
