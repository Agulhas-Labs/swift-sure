//
// Copyright © Agulhas Labs
//

/// What stops an `.xctestrun` being rewritten for a run with animations off.
public enum AnimationsOffError: Error, CustomStringConvertible, Sendable {
    /// The `.xctestrun` did not hold a dictionary at its root.
    case notADictionary
    /// The animations-off library could not be written or compiled; carries the compiler's first line of complaint.
    case libraryNotBuilt(String)

    public var description: String {
        switch self {
        case .notADictionary:
            "the .xctestrun does not hold a dictionary at its root"
        case let .libraryNotBuilt(detail):
            "the animations-off library could not be built: \(detail)"
        }
    }
}
