//
// Copyright © Agulhas Labs
//

/// What `diff`'s access section found for one declaration it looked up.
struct AccessFinding: Sendable {
    let subject: AccessSubject
    /// The module declaring it.
    let module: String
    let verdict: Verdict
    /// The name its uses were matched on over the working tree, `nil` where the index store resolved them.
    let nameMatchedOn: String?
    /// The files the index store does not cover as they stand, in a target the last build left out or changed since it, whose matches by name were counted beside the store's uses.
    var nameMatchedFiles: [String] = []
    /// How many files the store does not cover were name-matched, those holding no match among them.
    var uncoveredFileCount = 0
    /// Whether its module is a library product this repository publishes, so a `public` suggestion is a question.
    let published: Bool
}

extension AccessFinding {
    enum Verdict: Sendable, Equatable {
        /// No use outside its module, or only from test files importing that module `@testable`.
        case noUse(testable: Bool)
        /// A `public` declaration used only from these other modules of its own package.
        case packageOnly(users: [String])
        /// A use that needs the level it has.
        case needsLevel

        /// The narrowest level the uses allow, `nil` where they need the level as it stands.
        var suggestion: AccessLevel? {
            switch self {
            case .noUse: .internalLevel
            case .packageOnly: .packageLevel
            case .needsLevel: nil
            }
        }
    }
}
