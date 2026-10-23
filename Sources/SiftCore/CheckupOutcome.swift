//
// Copyright © Agulhas Labs
//

/// What one check of `checkup` found: its status and its findings.
public struct CheckupOutcome: Sendable, Equatable {
    let check: CheckupCheck
    let status: CheckupStatus
    let findings: [CheckupFinding]
}
