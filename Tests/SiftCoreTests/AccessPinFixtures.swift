//
// Copyright © Agulhas Labs
//

@testable import SiftCore

/// Builders for the access section's unit pins: subjects, findings and the subjects a source pair puts at the judged levels.
struct AccessPinFixtures {
    static func subject(
        _ name: String = "restock()",
        kind: SymbolKind = .function,
        level: AccessLevel = .publicLevel,
        widened: Bool = false,
        signature: String? = nil,
        containerName: String? = nil,
        containerInherited: [String] = []
    ) -> AccessSubject {
        AccessSubject(
            label: name,
            name: name,
            kind: kind,
            path: "Sources/GizmoKit/Gizmo.swift",
            line: 2,
            level: level,
            widened: widened,
            signature: signature ?? "\(level.rawValue) func \(name)",
            containerName: containerName,
            containerSignature: nil,
            containerInherited: containerInherited,
            extendedTypes: [],
            exclusion: nil
        )
    }

    static func finding(
        _ name: String = "restock()",
        level: AccessLevel = .publicLevel,
        module: String = "GizmoKit",
        verdict: AccessFinding.Verdict = .noUse(testable: false),
        widened: Bool = false,
        nameMatched: Bool = false,
        published: Bool = false
    ) -> AccessFinding {
        AccessFinding(
            subject: subject(name, level: level, widened: widened),
            module: module,
            verdict: verdict,
            nameMatchedOn: nameMatched ? "restock" : nil,
            published: published
        )
    }

    /// The subjects `old` to `new` put at `open`, `public` or `package`, as the diff's collector picks them.
    static func subjects(old: String?, new: String) -> [AccessSubject] {
        let path = "Sources/GizmoKit/Gizmo.swift"
        let newSide = DiffFileSide.parse(source: new, path: path)
        let changes = DeclarationDiff.changes(old: old.map { DiffFileSide.parse(source: $0, path: path) }, new: newSide)
        return AccessSubjectCollector.subjects(in: changes, newSide: newSide, path: path)
    }
}
