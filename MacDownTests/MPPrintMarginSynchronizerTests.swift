//
//  MPPrintMarginSynchronizerTests.swift
//  MacDownTests
//
//  The synchronizer must re-clamp an NSPrintInfo's margins when its paper size
//  changes (macdown-evb), and stop once invalidated.
//

import XCTest
import AppKit
@testable import MacDown

final class MPPrintMarginSynchronizerTests: XCTestCase {

    private func contentWidth(_ info: NSPrintInfo) -> CGFloat {
        return info.paperSize.width - info.leftMargin - info.rightMargin
    }

    /// Shrinking the paper below the requested margins must re-clamp them so a
    /// positive content strip remains. Were the observer not firing, the fixed
    /// 72+72 margins would exceed a 120pt-wide sheet and content width would go
    /// negative.
    func testReclampsWhenPaperSizeShrinks() {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        let sync = MPPrintMarginSynchronizer(
            printInfo: info, requestedTop: 72, left: 72, bottom: 72, right: 72)

        XCTAssertGreaterThan(contentWidth(info), 0,
                             "initial clamp should leave content")

        info.paperSize = NSSize(width: 120, height: 300)
        XCTAssertGreaterThan(contentWidth(info), 0,
                             "margins must re-clamp to fit the smaller sheet")

        sync.invalidate()
    }

    /// After -invalidate the synchronizer must stop reacting to paper changes.
    func testStopsAfterInvalidate() {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 120, height: 300)
        let sync = MPPrintMarginSynchronizer(
            printInfo: info, requestedTop: 72, left: 72, bottom: 72, right: 72)
        let clampedLeft = info.leftMargin

        sync.invalidate()
        info.paperSize = NSSize(width: 612, height: 792)

        XCTAssertEqual(info.leftMargin, clampedLeft,
                       "margins must not change after invalidate")
    }
}
