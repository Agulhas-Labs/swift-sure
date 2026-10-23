//
// Copyright © Agulhas Labs
//

/// One finding line of a `checkup` answer.
struct CheckupFinding: Sendable, Equatable {
    let findingClass: CheckupFindingClass
    let path: String?
    let line: Int?
    let endLine: Int?
    let text: String
    /// The command, spelled for this change, that shows the finding's detail.
    let command: String

    /// `path:line` or `path:first-last`; a finding about no one place has none.
    var location: String? {
        guard let path else { return nil }
        guard let line else { return path }
        guard let endLine, endLine > line else { return "\(path):\(line)" }
        return "\(path):\(line)-\(endLine)"
    }
}
