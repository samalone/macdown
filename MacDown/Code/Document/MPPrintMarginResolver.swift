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
        // into the non-printable border.
        let minLeft   = imageableRect.minX
        let minBottom = imageableRect.minY
        let minRight  = paperSize.width - imageableRect.maxX
        let minTop    = paperSize.height - imageableRect.maxY

        let top    = max(requested.top, minTop)
        let left   = max(requested.left, minLeft)
        let bottom = max(requested.bottom, minBottom)
        let right  = max(requested.right, minRight)

        let clamped = top > requested.top || left > requested.left
            || bottom > requested.bottom || right > requested.right

        let margins = MPPageMargins(top: top, left: left,
                                    bottom: bottom, right: right)
        return MPResolvedMargins(margins: margins, wasClamped: clamped)
    }
}
