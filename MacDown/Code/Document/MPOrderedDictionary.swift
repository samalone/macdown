//
//  MPOrderedDictionary.swift
//  MacDown
//
//  A minimal, insertion-order-preserving dictionary bridged to Objective-C,
//  replacing the vendored M13OrderedDictionary pod (bead macdown-j8g). Backed
//  by swift-collections' `OrderedDictionary`. Only the surface MacDown needs
//  is exposed: keyed lookup, ordered keys/values, insertion, and count.
//
//  Keys are strings (front-matter mapping keys are always scalars rendered as
//  strings); values are arbitrary Foundation objects — `NSString`, `NSArray`,
//  `NSNull`, or a nested `MPOrderedDictionary`. The front-matter parser builds
//  it; `-[… HTMLTable]` and MPDocument's title lookup consume it.
//

import Foundation
import OrderedCollections

@objc(MPOrderedDictionary)
final class MPOrderedDictionary: NSObject {

    private var storage = OrderedDictionary<String, Any>()

    // Parameters are optional so a nil from the Objective-C side is tolerated
    // at the bridge rather than trapping — matching the NSDictionary-backed
    // M13OrderedDictionary this replaces (whose objectForKey:nil returned nil).
    @objc(objectForKey:)
    func object(forKey key: String?) -> Any? {
        guard let key else { return nil }
        return storage[key]
    }

    @objc(setObject:forKey:)
    func setObject(_ object: Any?, forKey key: String?) {
        guard let key, let object else { return }
        storage[key] = object
    }

    /// Keys in insertion order.
    @objc var allKeys: [String] {
        Array(storage.keys)
    }

    /// Values in key order (parallel to `allKeys`).
    @objc var allObjects: [Any] {
        Array(storage.values)
    }

    @objc var count: Int {
        storage.count
    }
}
