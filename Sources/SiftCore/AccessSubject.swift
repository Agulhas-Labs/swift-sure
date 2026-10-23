//
// Copyright © Agulhas Labs
//

/// One declaration a range put at `open`, `public` or `package` — added there, or widened there — as `diff`'s access section judges it.
struct AccessSubject: Sendable {
    /// The declarations section's label for it: its container path and its name.
    let label: String
    let name: String
    let kind: SymbolKind
    let path: String
    /// Its after-side line.
    let line: Int
    /// Its own level capped by every enclosing type's this file declares.
    let level: AccessLevel
    let widened: Bool
    let signature: String
    /// The simple name of the type it is a member of, or the type an enclosing extension extends; `nil` at top level.
    let containerName: String?
    let containerSignature: String?
    /// The enclosing type's or extension's inheritance clause as written.
    let containerInherited: [String]
    /// Types an enclosing extension extends that this file does not declare, whose levels the index caps it by.
    let extendedTypes: [String]
    /// What its own head already says keeps it from being judged.
    var exclusion: AccessExclusion?
}
