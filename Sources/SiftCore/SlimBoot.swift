//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// What a slim boot is built from: the profile and the plan it yields for the project.
public struct SlimBoot: Sendable, Equatable {
    public let profile: ServiceProfile
    public let plan: SlimPlan
}
