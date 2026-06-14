//
//  MPPrintMarginResolverTests.swift
//  MacDownTests
//
//  Drives the first Swift unit through @testable import. Encodes defect #1 of
//  macdown-ppi.1: requested margins smaller than the printer's imageable area
//  must be clamped so content is not laid out into the non-printable border.
//

import XCTest
@testable import MacDown

final class MPPrintMarginResolverTests: XCTestCase {

    // US Letter (612x792 pt) with a 1/4" (18 pt) hardware margin on each edge.
    private let letter = CGSize(width: 612, height: 792)
    private var letterImageable: CGRect {
        CGRect(x: 18, y: 18, width: 612 - 36, height: 792 - 36)
    }

    /// Zero side margins (today's default) must be raised to at least the
    /// printer's 18 pt hardware margin; the already-generous top/bottom stay.
    func testZeroSideMarginsAreClampedToImageableArea() {
        let requested = MPPageMargins(top: 50, left: 0, bottom: 50, right: 0)
        let result = MPPrintMarginResolver.resolve(
            paperSize: letter,
            imageableRect: letterImageable,
            requested: requested)

        XCTAssertGreaterThanOrEqual(result.margins.left, 18)
        XCTAssertGreaterThanOrEqual(result.margins.right, 18)
        XCTAssertEqual(result.margins.top, 50)
        XCTAssertEqual(result.margins.bottom, 50)
        XCTAssertTrue(result.wasClamped)
    }

    /// Margins already inside the imageable area must be left untouched.
    func testGenerousMarginsAreLeftUntouched() {
        let requested = MPPageMargins(top: 72, left: 72, bottom: 72, right: 72)
        let result = MPPrintMarginResolver.resolve(
            paperSize: letter,
            imageableRect: letterImageable,
            requested: requested)

        XCTAssertEqual(result.margins, requested)
        XCTAssertFalse(result.wasClamped)
    }
}
