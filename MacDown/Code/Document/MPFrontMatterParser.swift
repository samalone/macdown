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
    static func object(fromYAMLString yaml: String?) -> Any? {
        // Require exactly one well-formed document. compose() returns the first
        // node and silently ignores trailing tokens; composeAll surfaces that
        // trailing junk as extra documents, so a count != 1 means malformed
        // front matter — which we reject (leaving the block visible as body
        // text), matching the old libyaml behavior.
        guard let yaml,
              let documents = try? composeAll(yaml: yaml),
              documents.count == 1
        else { return nil }
        // Callers expect a dictionary or nil — never hand back NSNull (e.g. an
        // empty or explicitly-null document).
        let object = convert(documents[0])
        return object is NSNull ? nil : object
    }

    private static func convert(_ node: YAML.Node) -> AnyObject {
        if let mapping = node.mapping {
            let dict = M13MutableOrderedDictionary<NSString, AnyObject>()
            for pair in mapping {
                dict.setObject(convert(pair.value), forKey: key(for: pair.key))
            }
            return dict
        }
        if let sequence = node.sequence {
            let array = NSMutableArray()
            for item in sequence {
                array.add(convert(item))
            }
            return array
        }
        if let scalar = node.scalar {
            return scalar.string as NSString
        }
        return NSNull()
    }

    /// Front-matter mapping keys are virtually always scalars. A complex
    /// (sequence/mapping) key — legal YAML but meaningless as metadata — is
    /// rendered to a distinct string so two such keys can't collide and drop
    /// each other's values.
    private static func key(for node: YAML.Node) -> NSString {
        if let scalar = node.scalar { return scalar.string as NSString }
        return String(describing: convert(node)) as NSString
    }
}
