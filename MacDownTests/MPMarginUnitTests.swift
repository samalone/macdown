//
//  MPMarginUnitTests.swift
//  MacDownTests
//
//  Locale-aware margin unit for the Print settings pane (macdown-wh6): an
//  inch locale must keep the 72 pt/inch factor; a metric locale must switch
//  to centimetres (72/2.54 pt/cm). The factor fully determines the unit
//  choice, so it is the deterministic signal under test.
//

import XCTest
@testable import MacDown

final class MPMarginUnitTests: XCTestCase {

    func testInchesForUSLocale() {
        let unit = MPMarginUnit(locale: Locale(identifier: "en_US"))
        XCTAssertEqual(unit.pointsPerUnit, 72.0, accuracy: 0.0001)
        XCTAssertFalse(unit.abbreviation.isEmpty)
    }

    func testCentimetresForMetricLocale() {
        let unit = MPMarginUnit(locale: Locale(identifier: "fr_FR"))
        // 1 cm = 1/2.54 inch, so 72/2.54 points per displayed unit.
        XCTAssertEqual(unit.pointsPerUnit, 72.0 / 2.54, accuracy: 0.0001)
        XCTAssertFalse(unit.abbreviation.isEmpty)
    }

    /// A round-trip points -> unit -> points must be lossless, which requires
    /// a strictly positive factor.
    func testFactorIsPositive() {
        let unit = MPMarginUnit(locale: Locale(identifier: "de_DE"))
        XCTAssertGreaterThan(unit.pointsPerUnit, 0)
    }
}
