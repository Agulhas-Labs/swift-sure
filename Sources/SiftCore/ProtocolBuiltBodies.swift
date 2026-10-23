//
// Copyright © Agulhas Labs
//

import SwiftParser
import SwiftSyntax

/// Reads, with no index store, which result builder builds each implied `.init call` that is a member's whole body (``ProtocolBuiltBody``), and holds the lines that say so beside an initializer's name-matched sites.
///
/// The builder comes from a requirement of the member's name, in a protocol the member's type conforms to by its own clause or an extension's, or in one such a protocol inherits. Where none declares one, the site is the stated type's, as it was scanned. Where one does, the site is no call of the stated type: it is said under each asked type a `buildExpression` of the builder takes (`buildBlock` where it declares none), and counted in no total; where the builder is not declared in the repository, or takes only generic types, the site is counted on one line saying it was not read.
final class ProtocolBuiltBodies {
    private let store: IndexStore
    /// Whether the scan's sites are read at all: an open index store resolves the calls itself, so its answer keeps them as scanned.
    private let reads: Bool
    private var readings: [ProtocolBuiltBody: Reading] = [:]
    /// The sites said under each asked type, with the builders that may make it.
    private var listed: [String: (sites: [SyntacticCallSite], builders: Set<String>)] = [:]
    /// The places of the sites no builder could be read for.
    private var unread: Set<String> = []
    private var failure: (any Error)?

    init(store: IndexStore, reads: Bool) {
        self.store = store
        self.reads = reads
    }

    /// The scan's sites with every member body a builder builds taken out: kept under the type it states where no requirement declares a builder, and under no other type.
    func reading(_ scanned: [String: [SyntacticCallSite]]) -> [String: [SyntacticCallSite]] {
        var kept: [String: [SyntacticCallSite]] = [:]
        for (name, sites) in scanned {
            kept[name] = sites.filter { keeps($0, under: name) }
        }
        return kept
    }

    /// The lines said beside the answer: the sites a builder may make each asked type with, then the count of those not read.
    func lines(cap: Int, filesCollector: WhereFilesCollector?) throws -> [String] {
        if let failure {
            throw failure
        }
        var lines: [String] = []
        for name in listed.keys.sorted() {
            guard var entry = listed[name] else { continue }
            entry.sites.sort { ($0.path, $0.line) < ($1.path, $1.line) }
            let count = entry.sites.count == 1 ? "once in a body" : "\(entry.sites.count) times in bodies"
            lines += ["", "an implicit .init is called \(count) \(entry.builders.sorted().joined(separator: " or ")) builds, a result builder taken from a protocol requirement, any of which may be \(name)'s; not counted above, verify before deleting:"]
            filesCollector?.recordSites(entry.sites)
            lines += NameMatchedSites.rows(Array(entry.sites.prefix(cap))) { "in \($0.enclosing)" }
            if entry.sites.count > cap {
                lines.append("    truncated: \(entry.sites.count - cap) more")
            }
        }
        if !unread.isEmpty {
            lines += [
                "",
                unread.count == 1
                    ? "1 body takes a result builder from a protocol requirement; implied .init in it is not read without a store"
                    : "\(unread.count) bodies take a result builder from a protocol requirement; implied .init in them is not read without a store",
            ]
        }
        return lines
    }

    /// Whether `site`, found under `name`, stays among that name's sites, noting it for the lines where a builder makes it.
    private func keeps(_ site: SyntacticCallSite, under name: String) -> Bool {
        guard let body = site.builtBody else { return true }
        guard reads else { return name == body.statedType }
        switch reading(of: body) {
        case .unbuilt:
            return name == body.statedType
        case let .built(builders, types):
            if types.contains(name), !(listed[name]?.sites.contains { $0.isSamePlace(as: site) } ?? false) {
                listed[name, default: ([], [])].sites.append(site)
                listed[name]?.builders.formUnion(builders)
            }
        case .unread:
            unread.insert("\(site.path):\(site.calleeAt ?? String(site.line))")
        }
        return false
    }

    private func reading(of body: ProtocolBuiltBody) -> Reading {
        if let known = readings[body] {
            return known
        }
        let reading: Reading
        do {
            reading = try read(body)
        } catch {
            failure = failure ?? error
            reading = .unbuilt
        }
        readings[body] = reading
        return reading
    }

    /// The builders the requirements of `body`'s name declare, across every protocol its type conforms to and those they inherit, and what they take.
    private func read(_ body: ProtocolBuiltBody) throws -> Reading {
        var queue: [String] = []
        for row in try store.typeDeclarations(named: body.type) where row.kind != .protocolKind {
            queue += try store.inheritedNames(of: row.id)
        }
        for row in try store.extensions(ofTypeNamed: body.type) {
            queue += try store.inheritedNames(of: row.id)
        }
        var seen: Set<String> = []
        var builders: Set<String> = []
        while let written = queue.popLast() {
            let name = DeclaredTypeName.last(ofPath: written)
            guard seen.insert(name).inserted else { continue }
            for row in try store.typeDeclarations(named: name) where row.kind == .protocolKind {
                for requirement in try store.children(of: row.id) where requirement.name == body.member {
                    builders.formUnion(AttributeScanner.customAttributeNames(in: requirement.signature).filter { !ImpliedInitType.compilerAttributes.contains($0) })
                }
                queue += try store.inheritedNames(of: row.id)
            }
        }
        var types: Set<String> = []
        var named: [String] = []
        for builder in builders.sorted() {
            let declared = try store.typeDeclarations(named: builder)
            let resultBuilders = declared.filter { AttributeScanner.attributeNames(in: $0.signature).contains("resultBuilder") }
            // A type of the name that is no result builder, a global actor say, builds nothing; one the repository does not declare cannot be read.
            guard !declared.isEmpty else { return .unread }
            guard !resultBuilders.isEmpty else { continue }
            let taken = try resultBuilders.flatMap { try takenTypes(by: $0) }
            guard !taken.isEmpty else { return .unread }
            types.formUnion(taken)
            named.append(builder)
        }
        return named.isEmpty ? .unbuilt : .built(builders: named, types: types)
    }

    /// The types the `buildExpression` overloads of `builder` take, or its `buildBlock` overloads where it declares none, leaving out a generic parameter.
    private func takenTypes(by builder: SymbolRow) throws -> [String] {
        let members = try store.children(of: builder.id)
        let expressions = members.filter { $0.baseName == "buildExpression" }
        return (expressions.isEmpty ? members.filter { $0.baseName == "buildBlock" } : expressions).compactMap { Self.firstParameterType(of: $0.signature) }
    }

    /// The simple name of the type a function's first parameter is declared with, an optional's wrapped type, or `nil` where it is one of the function's generic parameters, an opaque or existential type, or none is written.
    private static func firstParameterType(of signature: String) -> String? {
        let tree = Parser.parse(source: signature)
        guard let function = tree.statements.first?.item.as(FunctionDeclSyntax.self),
              let written = function.signature.parameterClause.parameters.first?.type,
              let type = ImpliedInitType.unwrapped(written, elementDepth: 0),
              type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) else { return nil }
        let generics = Set(function.genericParameterClause?.parameters.map(\.name.text) ?? [])
        let name = DeclaredTypeName.of(type)
        return generics.contains(name) ? nil : name
    }
}

extension ProtocolBuiltBodies {
    /// What a member's builder makes of its body.
    private enum Reading {
        /// No requirement declares a builder: the stated type builds the call.
        case unbuilt
        /// The builders, by name, and the types their expressions take.
        case built(builders: [String], types: Set<String>)
        /// A builder the repository does not declare, or one taking only generic types.
        case unread
    }
}
