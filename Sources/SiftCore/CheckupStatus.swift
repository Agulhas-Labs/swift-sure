//
// Copyright © Agulhas Labs
//

/// What became of one check: it ran, with the basis it stood on and any bound that stopped it part way, or it had no evidence to read.
enum CheckupStatus: Sendable, Equatable {
    /// `basis` is what the check stood on; `bound` counts what a bound left out.
    case checked(basis: String?, bound: String?)
    case notChecked(reason: String)
}
