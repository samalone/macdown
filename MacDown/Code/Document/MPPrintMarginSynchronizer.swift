//
//  MPPrintMarginSynchronizer.swift
//  MacDown
//
//  Keeps a print operation's margins clamped to the *currently selected* paper
//  (macdown-evb). MPDocument clamps once for the document's default paper, but
//  the print panel lets the user change paper size / orientation mid-session;
//  this observer re-runs the clamp whenever that happens, so content never
//  spills into the newly chosen sheet's non-imageable border and the panel's
//  live preview stays correct.
//

import AppKit

@objc(MPPrintMarginSynchronizer)
final class MPPrintMarginSynchronizer: NSObject {

    private let top: CGFloat
    private let left: CGFloat
    private let bottom: CGFloat
    private let right: CGFloat
    private var observations: [NSKeyValueObservation] = []

    /// Clamp `printInfo` now for the requested margins (in points), then keep
    /// it clamped as its paper size or orientation change.
    @objc(initWithPrintInfo:requestedTop:left:bottom:right:)
    init(printInfo: NSPrintInfo,
         requestedTop top: CGFloat, left: CGFloat,
         bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
        super.init()

        reclamp(printInfo)
        // The imageable area the clamp depends on is a function of paper size,
        // orientation, AND the destination printer (different printers have
        // different non-imageable borders). imageablePageBounds itself is not
        // KVO-observable, so observe those three inputs instead. (Each handler
        // is inline because the three key paths have different value types.)
        observations.append(
            printInfo.observe(\.paperSize, options: [.new]) {
                [weak self] info, _ in self?.reclamp(info)
            })
        observations.append(
            printInfo.observe(\.orientation, options: [.new]) {
                [weak self] info, _ in self?.reclamp(info)
            })
        observations.append(
            printInfo.observe(\.printer, options: [.new]) {
                [weak self] info, _ in self?.reclamp(info)
            })
    }

    deinit {
        invalidate()
    }

    /// Stop observing. Call when the print operation finishes.
    @objc func invalidate() {
        for observation in observations {
            observation.invalidate()
        }
        observations.removeAll()
    }

    private func reclamp(_ printInfo: NSPrintInfo) {
        // Re-derive from the requested margins each time (not the current,
        // already-clamped values) so the clamp is idempotent. Setting the
        // margins does not touch paperSize/orientation, so this can't recurse.
        MPPrintMarginController.applyMargins(to: printInfo,
                                             requestedTop: top, left: left,
                                             bottom: bottom, right: right)
    }
}
