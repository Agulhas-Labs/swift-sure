//
// Copyright © Agulhas Labs
//

/// The closed table `diff`'s access section judges a conformance to an outside protocol by when no store answers: each standard-library protocol with everything a conforming type may write to satisfy it, the marker protocols, which require nothing, and the protocols too wide to list.
///
/// A protocol in none of the lists is one whose requirements cannot be seen, so every member of a type conforming to it is left unjudged.
struct StandardLibraryRequirements {
    /// Protocols that require no member, so a conformance to one makes no member a witness.
    static let markers: Set<String> = ["Sendable", "BitwiseCopyable", "Copyable", "Escapable"]

    /// The sequence and collection protocols, whose customization points are too many to list exactly, so every member of a type conforming to one is left unjudged.
    static let unlisted: Set<String> = [
        "Sequence",
        "Collection",
        "BidirectionalCollection",
        "RandomAccessCollection",
        "MutableCollection",
        "RangeReplaceableCollection",
        "LazySequenceProtocol",
        "LazyCollectionProtocol",
    ]

    /// Each standard-library protocol whose requirements, customization points included, are listed exactly.
    static let protocols: [String: StandardLibraryProtocol] = [
        "Equatable": StandardLibraryProtocol(members: ["==(_:_:)"]),
        "Hashable": StandardLibraryProtocol(inherits: ["Equatable"], members: ["hash(into:)", "hashValue", "_rawHashValue(seed:)", "==(_:_:)"]),
        "Comparable": StandardLibraryProtocol(inherits: ["Equatable"], members: ["<(_:_:)", "<=(_:_:)", ">(_:_:)", ">=(_:_:)", "==(_:_:)"]),
        "Encodable": StandardLibraryProtocol(members: ["encode(to:)"]),
        "Decodable": StandardLibraryProtocol(members: ["init(from:)"]),
        "Codable": StandardLibraryProtocol(inherits: ["Encodable", "Decodable"], members: ["encode(to:)", "init(from:)"]),
        "CustomStringConvertible": StandardLibraryProtocol(members: ["description"]),
        "CustomDebugStringConvertible": StandardLibraryProtocol(members: ["debugDescription"]),
        "LosslessStringConvertible": StandardLibraryProtocol(inherits: ["CustomStringConvertible"], members: ["init(_:)", "description"]),
        "Identifiable": StandardLibraryProtocol(members: ["id"], associatedTypes: ["ID"]),
        "Error": StandardLibraryProtocol(inherits: ["Sendable"], members: ["_domain", "_code", "_userInfo", "_getEmbeddedNSError()"]),
        "LocalizedError": StandardLibraryProtocol(
            inherits: ["Error"],
            members: ["errorDescription", "failureReason", "recoverySuggestion", "helpAnchor", "_domain", "_code", "_userInfo", "_getEmbeddedNSError()"]
        ),
        "RawRepresentable": StandardLibraryProtocol(members: ["rawValue", "init(rawValue:)"], associatedTypes: ["RawValue"]),
        "CaseIterable": StandardLibraryProtocol(members: ["allCases"], associatedTypes: ["AllCases"]),
        "CodingKey": StandardLibraryProtocol(
            inherits: ["Sendable", "CustomStringConvertible", "CustomDebugStringConvertible"],
            members: ["stringValue", "intValue", "init(stringValue:)", "init(intValue:)", "description", "debugDescription"]
        ),
        "IteratorProtocol": StandardLibraryProtocol(members: ["next()"], associatedTypes: ["Element"]),
        "AsyncIteratorProtocol": StandardLibraryProtocol(members: ["next()", "next(isolation:)"], associatedTypes: ["Element", "Failure"]),
        "AsyncSequence": StandardLibraryProtocol(members: ["makeAsyncIterator()"], associatedTypes: ["AsyncIterator", "Element", "Failure"]),
        "Strideable": StandardLibraryProtocol(
            inherits: ["Comparable"],
            members: ["distance(to:)", "advanced(by:)", "_step(after:from:by:)", "<(_:_:)", "<=(_:_:)", ">(_:_:)", ">=(_:_:)", "==(_:_:)"],
            associatedTypes: ["Stride"]
        ),
        "TextOutputStream": StandardLibraryProtocol(members: ["write(_:)", "_lock()", "_unlock()"]),
        "TextOutputStreamable": StandardLibraryProtocol(members: ["write(to:)"]),
        "ExpressibleByUnicodeScalarLiteral": StandardLibraryProtocol(members: ["init(unicodeScalarLiteral:)"], associatedTypes: ["UnicodeScalarLiteralType"]),
        "ExpressibleByExtendedGraphemeClusterLiteral": StandardLibraryProtocol(
            inherits: ["ExpressibleByUnicodeScalarLiteral"],
            members: ["init(extendedGraphemeClusterLiteral:)", "init(unicodeScalarLiteral:)"],
            associatedTypes: ["ExtendedGraphemeClusterLiteralType", "UnicodeScalarLiteralType"]
        ),
        "ExpressibleByStringLiteral": StandardLibraryProtocol(
            inherits: ["ExpressibleByExtendedGraphemeClusterLiteral"],
            members: ["init(stringLiteral:)", "init(extendedGraphemeClusterLiteral:)", "init(unicodeScalarLiteral:)"],
            associatedTypes: ["StringLiteralType", "ExtendedGraphemeClusterLiteralType", "UnicodeScalarLiteralType"]
        ),
        "ExpressibleByIntegerLiteral": StandardLibraryProtocol(members: ["init(integerLiteral:)"], associatedTypes: ["IntegerLiteralType"]),
        "ExpressibleByFloatLiteral": StandardLibraryProtocol(members: ["init(floatLiteral:)"], associatedTypes: ["FloatLiteralType"]),
        "ExpressibleByBooleanLiteral": StandardLibraryProtocol(members: ["init(booleanLiteral:)"], associatedTypes: ["BooleanLiteralType"]),
        "ExpressibleByArrayLiteral": StandardLibraryProtocol(members: ["init(arrayLiteral:)"], associatedTypes: ["ArrayLiteralElement"]),
        "ExpressibleByDictionaryLiteral": StandardLibraryProtocol(members: ["init(dictionaryLiteral:)"], associatedTypes: ["Key", "Value"]),
        "ExpressibleByNilLiteral": StandardLibraryProtocol(members: ["init(nilLiteral:)"]),
    ]
}
