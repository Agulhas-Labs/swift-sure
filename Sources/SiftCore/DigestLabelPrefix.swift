//
// Copyright © Agulhas Labs
//

import Foundation

struct DigestLabelPrefix {
    let renderer: DigestRenderer

    /// The answer to a `Type.member(labels…)` target that names no member exactly but whose written labels begin the labels of members of that type, or `nil` where none does or no label is written (`()` begins every list, so it names nothing).
    ///
    /// One such member is answered as its full signature would be, under a line saying so; several keep the refusal but list only them, since a caller who wrote `init(opening:)` knew the member and is not helped by the twelve nearest symbols of the index. A memberwise initializer the compiler writes counts as one of them.
    func answer(target: String, options: DigestOptions) throws -> Answer? {
        let components = QualifiedPath.components(of: target)
        guard components.count >= 2, let written = components.last, let open = written.firstIndex(of: "("), written.hasSuffix(")") else { return nil }
        let writtenLabels = Self.labels(of: written)
        guard !writtenLabels.isEmpty else { return nil }
        let base = String(written[..<open])
        let owner = components.dropLast().joined(separator: ".")
        let candidates = try WhereRenderer(store: renderer.store)
            .declarations(for: "\(owner).\(base)")
            .filter { !$0.kind.isContainer }
        let declared = candidates.filter { Self.begins(Self.labels(of: $0.name), with: writtenLabels) }
        var synthesized: [(label: String, found: SynthesizedInitializer.Found)] = []
        if base == "init" {
            let repoRoot = renderer.repoRoot
            for found in try SynthesizedInitializer(store: renderer.store, source: { row in
                guard case let .lines(lines, _) = SourceSlicer.slice(of: row, under: repoRoot) else { return nil }
                return lines
            }).lookup(target: "\(owner).init") {
                let labels = (found.parameters ?? []).map { String($0.prefix { $0 != ":" }) }
                if Self.begins(labels, with: writtenLabels) {
                    synthesized.append(("init(" + labels.map { "\($0):" }.joined() + ")", found))
                }
            }
        }
        let total = declared.count + synthesized.count
        guard total > 0 else { return nil }
        let typeName = components[components.count - 2]
        let begin = writtenLabels.map { "\($0):" }.joined()
        if total == 1 {
            if let first = declared.first {
                let full = "\(owner).\(first.name)"
                guard let body = try renderer.renderDeclaredMemberBody(target: full, options: options) else { return nil }
                return Answer(text: "resolved \(written) to \(first.name) (the only \(base) on \(typeName) whose labels begin \(begin))\n" + body, missed: false)
            }
            let only = synthesized[0]
            let paths = [only.found.path]
            let banners = try renderer.parseErrorBanner(touching: paths) + renderer.guessedModuleBanner(touching: paths)
            let lines = banners + ["resolved \(written) to \(only.label) (the only \(base) on \(typeName) whose labels begin \(begin))"] + SynthesizedInitializer.lines(for: only.found)
            return Answer(text: lines.joined(separator: "\n"), missed: false)
        }
        var lines = try renderer.absenceBanner()
        lines.append("no member named \(written) on \(typeName); \(total) begin with those labels:")
        for row in declared {
            lines.append("  \(row.name) — \(row.kind.rawValue) — \(row.module) — \(row.path):\(row.line)")
        }
        for entry in synthesized {
            lines.append("  \(entry.label) — synthesized initializer — \(entry.found.path)\(entry.found.rangeDescription)")
        }
        // The pointer a plain miss carries: the whole written target, as that answer probes it.
        if let siblingRoots = renderer.siblingRoots {
            let pointers = siblingRoots(target)
            if !pointers.isEmpty {
                lines += [""] + pointers.map { $0.line(for: target, spelling: options.spelling) }
            }
        }
        return Answer(text: lines.joined(separator: "\n"), missed: true)
    }

    /// Whether `written` is a proper prefix of `labels`.
    private static func begins(_ labels: [String], with written: [String]) -> Bool {
        labels.count > written.count && Array(labels.prefix(written.count)) == written
    }

    /// The argument labels of a stored or written name, `_` included: `save(_:to:)` → `["_", "to"]`.
    private static func labels(of name: String) -> [String] {
        guard let open = name.firstIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else { return [] }
        return name[name.index(after: open) ..< close].split(separator: ":", omittingEmptySubsequences: false).dropLast().map(String.init)
    }
}

extension DigestLabelPrefix {
    /// What a prefix lookup answers, and whether it counts as a hit: one member resolved is, the several-match refusal is not.
    struct Answer {
        let text: String
        let missed: Bool
    }
}
