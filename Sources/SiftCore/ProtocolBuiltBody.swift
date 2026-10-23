//
// Copyright © Agulhas Labs
//

/// A member of a type whose whole body is an implied `.init call` and which carries no builder attribute of its own, so a result builder a requirement of its name in a protocol the type conforms to may build the call in place of the type the member states.
struct ProtocolBuiltBody: Sendable, Hashable {
    /// The simple name of the type, or the extended type, the member is declared in.
    let type: String
    /// The member's name as the index records it — `body`, `make(_:)`, `subscript(_:)`.
    let member: String
    /// The type the member states, which the call builds where no builder does.
    let statedType: String
}
