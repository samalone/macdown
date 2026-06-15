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

    /// Changing orientation must also re-clamp. Vertical margins that fit the
    /// 792pt-tall portrait page exceed the 612pt-tall landscape page, so they
    /// must shrink when the user flips to landscape.
    func testReclampsWhenOrientationChanges() {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        let sync = MPPrintMarginSynchronizer(
            printInfo: info, requestedTop: 350, left: 72, bottom: 350,
            right: 72)
        XCTAssertGreaterThan(792 - info.topMargin - info.bottomMargin, 0,
                             "portrait margins should fit the tall page")

        info.orientation = .landscape
        // The landscape page is 612pt tall (the portrait width). Without a
        // re-clamp the 350+350 margins would exceed it and content would go
        // negative.
        let landscapeHeight: CGFloat = info.paperSize.width
        XCTAssertGreaterThan(
            landscapeHeight - info.topMargin - info.bottomMargin, 0,
            "margins must re-clamp when orientation flips to landscape")

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
