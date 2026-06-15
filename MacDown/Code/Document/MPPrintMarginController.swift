//
//  MPPrintMarginController.swift
//  MacDown
//
//  Objective-C entry point that bridges MPDocument's printing to the pure
//  MPPrintMarginResolver (macdown-ppi.1 / macdown-5xp.1). Swift structs aren't
//  visible to Objective-C, so this thin @objc class does the NSPrintInfo I/O
//  and delegates the geometry to the (separately unit-tested) resolver.
//

import AppKit

@objc(MPPrintMarginController)
final class MPPrintMarginController: NSObject {

    /// Clamp the requested margins (in points) up to the printer's imageable
    /// area for `printInfo`'s current paper, and apply the result to
    /// `printInfo`. Returns whether any margin had to be enlarged — a caller
    /// may use this to warn that the requested margins were too small.
    @objc(applyMarginsToPrintInfo:requestedTop:left:bottom:right:)
    @discardableResult
    static func applyMargins(to printInfo: NSPrintInfo,
                             requestedTop top: CGFloat,
                             left: CGFloat,
                             bottom: CGFloat,
                             right: CGFloat) -> Bool {
        let requested = MPPageMargins(top: top, left: left,
                                      bottom: bottom, right: right)
        // Read the imageable bounds before mutating margins: it reflects the
        // printer's imageable area for the current paper and orientation.
        let resolved = MPPrintMarginResolver.resolve(
            paperSize: orientedPaperSize(for: printInfo),
            imageableRect: printInfo.imageablePageBounds,
            requested: requested)
        printInfo.topMargin = resolved.margins.top
        printInfo.leftMargin = resolved.margins.left
        printInfo.bottomMargin = resolved.margins.bottom
        printInfo.rightMargin = resolved.margins.right
        return resolved.wasClamped
    }

    /// `printInfo.paperSize` is always reported in portrait, but
    /// `imageablePageBounds` (and the printed page) follow the orientation.
    /// Return the paper size with its dimensions swapped for landscape, so the
    /// two agree — used both for the margin clamp and for seeding the
    /// WKPrintingView frame.
    @objc(orientedPaperSizeForPrintInfo:)
    static func orientedPaperSize(for printInfo: NSPrintInfo) -> CGSize {
        let size = printInfo.paperSize
        if printInfo.orientation == .landscape && size.width < size.height {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }
}
