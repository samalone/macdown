//
//  MPPrintMarginResolver.swift
//  MacDown
//
//  First Swift component (macdown-5xp.1 / macdown-ppi.1). Pure geometry:
//  reconcile a user's preferred print margins with the printer's imageable
//  area so content is never laid out into the non-printable border (which
//  causes clipping — "printing beyond the printable area").
//
//  Swift house style for this fork: Swift-idiomatic same-line braces (not the
//  Allman style CONTRIBUTING.md mandates for Objective-C), 4-space indent,
//  80-column limit.
//

import CoreGraphics

/// Per-side page margins, in points.
struct MPPageMargins: Equatable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat
}

/// The outcome of reconciling requested margins with a printer's imageable
/// area.
struct MPResolvedMargins: Equatable {
    var margins: MPPageMargins
    /// True when one or more requested margins were smaller than the printer's
    /// imageable area allows and had to be enlarged.
    var wasClamped: Bool
}

enum MPPrintMarginResolver {

    /// Enlarge any of `requested`'s margins that would push content into the
    /// printer's non-imageable border, so the laid-out content stays within
    /// `imageableRect`.
    ///
    /// - Parameters:
    ///   - paperSize: full paper size in points (e.g. 612x792 for US Letter).
    ///   - imageableRect: the printable rectangle within the paper, origin at
    ///     the lower-left, matching `NSPrintInfo.imageablePageBounds`.
    ///   - requested: the user's preferred margins.
    /// - Returns: the effective margins plus whether clamping occurred.
    static func resolve(paperSize: CGSize,
                        imageableRect: CGRect,
                        requested: MPPageMargins) -> MPResolvedMargins {
        // The imageable rectangle (origin lower-left) implies the smallest
        // margin the printer can honour on each side; anything smaller spills
        // into the non-printable border. Guard a degenerate (empty) imageable
        // rect — some virtual/PDF printers report CGRectZero — by imposing no
        // minimum rather than clamping the entire sheet away. Negative insets
        // (imageable larger than the sheet) are floored at zero.
        let hasImageable = imageableRect.width > 0 && imageableRect.height > 0
        let minLeft   = hasImageable ? max(imageableRect.minX, 0) : 0
        let minBottom = hasImageable ? max(imageableRect.minY, 0) : 0
        let minRight  = hasImageable
            ? max(paperSize.width - imageableRect.maxX, 0) : 0
        let minTop    = hasImageable
            ? max(paperSize.height - imageableRect.maxY, 0) : 0

        let (left, right) = clampAxis(paper: paperSize.width,
                                      minA: minLeft, minB: minRight,
                                      reqA: requested.left, reqB: requested.right)
        let (top, bottom) = clampAxis(paper: paperSize.height,
                                      minA: minTop, minB: minBottom,
                                      reqA: requested.top, reqB: requested.bottom)

        let margins = MPPageMargins(top: top, left: left,
                                    bottom: bottom, right: right)
        return MPResolvedMargins(margins: margins,
                                 wasClamped: margins != requested)
    }

    /// Resolve the two margins along one axis: raise each to its printer
    /// minimum, then — if together they would leave no printable strip — shrink
    /// them back toward those minimums so at least `minContentLength` remains.
    /// Without this an over-large margin (e.g. 5" + 5" on an 8.5" sheet) would
    /// give a zero/negative content width and WebKit would emit blank pages.
    private static func clampAxis(paper: CGFloat,
                                  minA: CGFloat, minB: CGFloat,
                                  reqA: CGFloat, reqB: CGFloat)
        -> (CGFloat, CGFloat) {
        var a = max(reqA, minA)
        var b = max(reqB, minB)

        let maxTotal = paper - minContentLength(for: paper)
        let slack = (a - minA) + (b - minB)
        if a + b > maxTotal && slack > 0 {
            // Shrink each margin toward its minimum in proportion to how far it
            // currently exceeds that minimum.
            let take = min(a + b - maxTotal, slack)
            a -= (a - minA) / slack * take
            b -= (b - minB) / slack * take
        }
        return (a, b)
    }

    /// The smallest content strip to insist on leaving along an axis: one inch,
    /// or half the sheet for very small paper.
    private static func minContentLength(for paper: CGFloat) -> CGFloat {
        return min(72.0, paper * 0.5)
    }
}
