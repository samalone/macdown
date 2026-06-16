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

    @objc(objectForKey:)
    func object(forKey key: String) -> Any? {
        storage[key]
    }

    @objc(setObject:forKey:)
    func setObject(_ object: Any, forKey key: String) {
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
