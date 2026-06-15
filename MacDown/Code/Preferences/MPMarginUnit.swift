//
//  MPMarginUnit.swift
//  MacDown
//
//  Locale-aware display unit for the Print settings pane's margin fields
//  (macdown-wh6). Margins are stored in points; this picks inches or
//  centimetres from the user's locale and vends both the points<->display
//  conversion factor and the localized unit symbol the pane shows. A thin
//  @objc bridge so the Objective-C pane can stay in Objective-C.
//
//  Swift house style for this fork: same-line braces (not the Allman style
//  CONTRIBUTING.md mandates for Objective-C), 4-space indent, 80 columns.
//

import Foundation

@objc(MPMarginUnit)
final class MPMarginUnit: NSObject {

    /// Points per displayed unit. The pane's value transformer divides stored
    /// points by this to show a value and multiplies on the way back: 72 for
    /// inches, 72/2.54 ≈ 28.35 for centimetres.
    @objc let pointsPerUnit: CGFloat

    /// Localized unit symbol shown after each field and in the header
    /// (e.g. "in", "cm").
    @objc let abbreviation: String

    /// The margin unit appropriate to `locale`: centimetres where the locale
    /// uses the metric system, inches otherwise.
    @objc(initWithLocale:)
    init(locale: Locale) {
        let unit: UnitLength =
            MPMarginUnit.usesMetricSystem(locale) ? .centimeters : .inches

        // Express one display unit in inches, then in points (72 pt/inch), so
        // the factor is exact whichever unit was picked.
        let inchesPerUnit =
            Measurement(value: 1, unit: unit).converted(to: .inches).value
        self.pointsPerUnit = CGFloat(inchesPerUnit * 72.0)

        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        self.abbreviation = formatter.string(from: unit)

        super.init()
    }

    /// The margin unit for the user's current locale.
    @objc static var current: MPMarginUnit {
        MPMarginUnit(locale: .current)
    }

    private static func usesMetricSystem(_ locale: Locale) -> Bool {
        if #available(macOS 13.0, *) {
            // .us is the only inch-using system here; .uk uses metric length.
            return locale.measurementSystem != .us
        } else {
            return locale.usesMetricSystem
        }
    }
}
