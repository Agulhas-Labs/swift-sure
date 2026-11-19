//
// Copyright © Agulhas Labs
//

import Foundation

/// What each file a scan read writes immediately before `.name`, for each name it found there: enough to tell, without reading the file again, that it never spells `Owner.name`.
///
/// A too-common name is followed only where its owner qualifies it (`OwnerQualifiedMentions`), and that check would otherwise read back every file writing the name, which for a name like `line` is a large share of the repository, on every hop. The scanners already hold each file's source, so they record this beside the sites, for the names they found in that file and no others. A file with no record is one no scan checked, and is read.
struct MemberSpellings: Sendable {
    /// The record for each name, by the path of the file it was read from.
    private(set) var byName: [String: [String: InFile]] = [:]

    init() {}

    /// The records of `names` in the file at `path`, read from its `source`; a name outside ASCII identifier characters gets none, so its file is always read.
    init(of names: some Sequence<String>, path: String, source: String) {
        for name in names {
            byName[name] = Self.inFile(name, source: source).map { [path: $0] }
        }
    }

    /// Adds `other`'s records; a file recorded by both keeps `other`'s, read from the same text.
    mutating func merge(_ other: MemberSpellings) {
        byName.merge(other.byName) { $0.merging($1) { $1 } }
    }

    /// Whether the file at `path` may write `name` qualified by one of `owners`: false only where its record shows it spells none of `Owner.name` and `>.name`, the text `OwnerQualifiedMentions` reads a file to look for.
    ///
    /// It never rules out a file that text check would pass: an owner the record cannot answer for, empty or written with anything but ASCII identifier characters, leaves the file to be read.
    func mayQualify(_ name: String, path: String, owners: Set<String>) -> Bool {
        guard let record = byName[name]?[path] else { return true }
        return record.afterGeneric || owners.contains { owner in
            owner.isEmpty || !owner.utf8.allSatisfy(Self.isIdentifierByte) || record.qualifiers.contains { $0.hasSuffix(owner) }
        }
    }

    private static func inFile(_ name: String, source: String) -> InFile? {
        guard !name.isEmpty, name.utf8.allSatisfy(isIdentifierByte) else { return nil }
        let target = Array(name.utf8)
        let utf8 = source.utf8
        return utf8.withContiguousStorageIfAvailable { inFile(target, bytes: $0) } ?? Array(utf8).withUnsafeBufferPointer { inFile(target, bytes: $0) }
    }

    private static func inFile(_ name: [UInt8], bytes: UnsafeBufferPointer<UInt8>) -> InFile {
        var record = InFile()
        var dot = 0
        while dot + name.count < bytes.count {
            defer { dot += 1 }
            guard bytes[dot] == UInt8(ascii: "."), name.indices.allSatisfy({ bytes[dot + 1 + $0] == name[$0] }) else { continue }
            var start = dot
            while start > 0, isIdentifierByte(bytes[start - 1]) {
                start -= 1
            }
            // ASCII identifier bytes, so the text is always valid UTF-8.
            if start < dot, let qualifier = String(bytes: bytes[start ..< dot], encoding: .utf8) {
                record.qualifiers.insert(qualifier)
            } else if dot > 0, bytes[dot - 1] == UInt8(ascii: ">") {
                record.afterGeneric = true
            }
        }
        return record
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "_"):
            true
        default:
            false
        }
    }
}

extension MemberSpellings {
    /// How one file writes one name after a `.`.
    struct InFile: Sendable, Equatable {
        /// The run of ASCII identifier characters written immediately before each `.name`, which is matched as text, so `.lines` counts too: `Lib.Gizmo.line` records `Gizmo`, `x.line` records `x`, and `(a).line` records nothing.
        var qualifiers: Set<String> = []
        /// Whether `>.name` is written: a specialized owner, `Gizmo<Int>.line`.
        var afterGeneric = false
    }
}
