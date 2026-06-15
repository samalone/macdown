//
//  MPFrontMatterParser.swift
//  MacDown
//
//  Parses YAML front matter with the pure-Swift `swift-yaml` package,
//  replacing the libyaml-backed YAMLSerialization wrapper (bead macdown-5mi).
//
//  The returned Foundation objects mirror what YAMLSerialization produced with
//  kYAMLReadOptionStringScalars, so the existing consumers keep working
//  unchanged: an ordered mapping becomes an M13MutableOrderedDictionary (so
//  `-[… HTMLTable]` renders front-matter rows in author order), a sequence
//  becomes an NSArray, and every scalar becomes an NSString.
//

import Foundation
import YAML

@objc final class MPFrontMatterParser: NSObject {

    /// Returns the first YAML document in `yaml` as Foundation objects, or
    /// `nil` if it is empty, not a YAML document, or fails to parse.
    @objc(objectFromYAMLString:)
    static func object(fromYAMLString yaml: String) -> Any? {
        guard let node = try? compose(yaml: yaml) else { return nil }
        return convert(node)
    }

    private static func convert(_ node: YAML.Node) -> Any {
        if let mapping = node.mapping {
            let dict = M13MutableOrderedDictionary<NSString, AnyObject>()
            for i in 0 ..< mapping.count {
                let pair = mapping[i]
                let key = (pair.key.scalar?.string ?? "") as NSString
                dict.setObject(convert(pair.value) as AnyObject, forKey: key)
            }
            return dict
        }
        if let sequence = node.sequence {
            let array = NSMutableArray()
            for i in 0 ..< sequence.count {
                array.add(convert(sequence[i]))
            }
            return array
        }
        if let scalar = node.scalar {
            return scalar.string as NSString
        }
        return NSNull()
    }
}
