//
//  MPPrintMarginSynchronizer.swift
//  MacDown
//
//  Keeps a print operation's margins clamped to the *currently selected*
//  imageable area while the print panel is open (macdown-evb). MPDocument
//  clamps once in -printInfo, but the imageable area can still change in the
//  panel — primarily by switching the destination printer (different printers
//  have different non-imageable borders). This observer re-runs the clamp when
//  that happens, so content never spills into the new printer's border.
//
//  Note: on current macOS, paper size and orientation are changed via Page
//  Setup, not the print panel; those route through -printInfo on the next
//  print. paperSize/orientation are still observed here so the clamp stays
//  correct on any system (or driver) that does expose them in the panel.
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
