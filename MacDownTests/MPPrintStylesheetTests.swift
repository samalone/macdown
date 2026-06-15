//
//  MPPrintStylesheetTests.swift
//  MacDownTests
//
//  Pins the MacDown-owned print stylesheet (macdown-ppi.1): the rules that
//  steer page breaks for print/PDF must ship in the app bundle and must stay
//  scoped to @media print so the on-screen preview is untouched.
//

import XCTest
@testable import MacDown

final class MPPrintStylesheetTests: XCTestCase {

    private func printCSS() throws -> String {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "print", withExtension: "css"),
            "print.css must be bundled with the app")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The rules must not bleed into the on-screen preview.
    func testPrintStylesheetIsScopedToPrintMedia() throws {
        let css = try printCSS()
        XCTAssertTrue(css.contains("@media print"),
                      "print rules must be scoped to @media print")
    }

    /// The declarations that keep text off page boundaries must be present.
    func testPrintStylesheetKeepsTextBlocksWhole() throws {
        let css = try printCSS()
        XCTAssertTrue(css.contains("break-inside: avoid"),
                      "blocks like <pre> must not split across pages")
        XCTAssertTrue(css.contains("break-after: avoid"),
                      "headings must stay with the following content")
        XCTAssertTrue(css.contains("orphans: 3"),
                      "paragraphs must not strand a line at a page bottom")
        XCTAssertTrue(css.contains("widows: 3"),
                      "paragraphs must not widow a line at a page top")
    }
}
