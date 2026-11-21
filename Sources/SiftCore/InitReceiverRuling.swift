//
// Copyright © Agulhas Labs
//

import Foundation

/// The receivers an initializer's unapplied `Receiver.init` cannot name, read from what the index declares and from the standard library or Foundation.
///
/// A receiver is ruled out for the initializers of a type only where it provably cannot be that type, a subclass of it or an alias of it: a standard-library or Foundation nominal the repository does not declare, ruled out everywhere, or a struct, enum or actor of another name, or a class outside the type's subclasses where the type is a class, ruled out only outside every type, extension and protocol declaration of the scanned file, since inside one a conformance or a generic extension can bring an associated type or generic parameter of that name into scope unwritten (`extension [Gizmo]` binds `Element`). A closed standard name an SDK declares as an associated type, type alias or generic parameter (`sdkBoundNames`: SwiftUI's `DynamicViewContent.Data`, `CollectionRangeSubscript`'s `Range`) is treated like a name the index declares; the rest are ruled out everywhere. The residual risk, not read: a dependency outside the index binding one of them (an associated type or type alias, or a generic parameter an `extension Depot` of `Depot<Data>` sees), an Objective-C lightweight generic parameter an SDK header declares, and an SDK newer than the one the list was derived from, since nothing re-derives it but a re-run of the script. Where the type is a protocol, or an extension's type the index does not resolve to a nominal type, nothing is ruled out, since a protocol extension's initializer is reached through any conformer. A name any indexed type declares as a generic parameter is never ruled out, since a file elsewhere may write it for a constrained type.
final class InitReceiverRuling: @unchecked Sendable {
    private static let standardNames: Set<String> = [
        "String", "Substring", "Character", "Bool", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Array", "Dictionary", "Set", "Range", "ClosedRange", "Data", "URL", "Date", "UUID",
    ]
    /// The closed standard names an installed SDK or the standard library declares as an associated type, a type alias or a generic parameter (SwiftUI's `associatedtype Data`, `typealias Data = Content.Data` and `ForEach<Data, …>`, `CollectionRangeSubscript<Wrapped, Range>`), ruled out only where an index-declared name is.
    ///
    /// Derived from Xcode 27.2 (27B52), the macOS 27.2 and iOS 27.2 SDKs and the toolchain's `usr/lib/swift`, by `Scripts/sdk-generic-names.sh`: every `*.swiftinterface` there (Objective-C headers are not read), a name having a hit where a line reads `associatedtype <Name>` or `typealias <Name>`, or where it opens a parameter of the generic parameter clause after a declaration's name; re-run it after an SDK update and keep this list equal to its output.
    private static let sdkBoundNames: Set<String> = ["Data", "Range"]
    private static let valueKinds: Set<SymbolKind> = [.structKind, .enumKind, .actor]
    private static let nominalKinds: Set<SymbolKind> = [.structKind, .enumKind, .actor, .classKind]

    private let index: IndexStore
    private let lock = NSLock()
    private var declaredKinds: [String: Set<SymbolKind>]?
    private var genericNames: Set<String> = []
    private var aliases: [String: Set<String>] = [:]
    private var ruled: [String: Receivers] = [:]

    /// A ruling over `index`, read only when a scan first asks for a receiver set.
    init(index: IndexStore) {
        self.index = index
    }

    /// The receiver names ruled out for an initializer declared in `parent`, a type or an extension of one, each with where it is ruled out; none where the index cannot be read.
    func receivers(ruledOutForInitIn parent: String) -> Receivers {
        lock.lock()
        defer { lock.unlock() }
        let type = DeclaredTypeName.last(ofPath: parent)
        if let known = ruled[type] {
            return known
        }
        guard let result = try? compute(for: type) else { return Receivers() }
        ruled[type] = result
        return result
    }

    private func compute(for type: String) throws -> Receivers {
        let declared = try declaredKindsLoaded()
        guard let kinds = declared[type], !kinds.isEmpty, kinds.isSubset(of: Self.nominalKinds) else { return Receivers() }
        let subclasses = kinds == [.classKind] ? try MemberReceivers(store: index).reaching(type, aliases: aliases) : nil
        var result = Receivers()
        let undeclared = Self.standardNames.filter { declared[$0] == nil && !genericNames.contains($0) && $0 != type }
        result.everywhere = undeclared.subtracting(Self.sdkBoundNames)
        result.outsideTypeDeclarations = undeclared.intersection(Self.sdkBoundNames)
        for (name, kindsOfName) in declared where name != type && !genericNames.contains(name) && kindsOfName.isSubset(of: Self.nominalKinds) {
            if kindsOfName.isSubset(of: Self.valueKinds) {
                result.outsideTypeDeclarations.insert(name)
            } else if let subclasses, !subclasses.contains(name) {
                result.outsideTypeDeclarations.insert(name)
            }
        }
        return result
    }

    private func declaredKindsLoaded() throws -> [String: Set<SymbolKind>] {
        if let declaredKinds {
            return declaredKinds
        }
        var kinds: [String: Set<SymbolKind>] = [:]
        var generics: Set<String> = []
        for row in try index.everyTypeLike() {
            kinds[DeclaredTypeName.last(ofPath: row.name), default: []].insert(row.kind)
            if row.kind != .typealiasKind, row.kind != .associatedType {
                generics.formUnion(SameNamedTypes.Resolver.genericParameters(of: row))
            }
        }
        genericNames = generics
        aliases = try MemberReceivers.aliasedNames(in: index.everyTypealias())
        declaredKinds = kinds
        return kinds
    }
}

extension InitReceiverRuling {
    /// Where an initializer's unapplied `Receiver.init` is ruled out, by receiver name.
    struct Receivers {
        /// Standard-library and Foundation names the index does not declare and no SDK binds: ruled out wherever the scanned file does not rebind them.
        var everywhere: Set<String> = []
        /// Names the index declares as another type, and standard names an SDK binds as an associated type or generic parameter: ruled out only at a use outside every type, extension and protocol declaration of the scanned file.
        var outsideTypeDeclarations: Set<String> = []
    }
}
