//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// Whether the shards boot slim or stock.
public enum BootMode: Sendable, Equatable {
    case slim(SlimBoot)
    case stock(StockReason)

    /// Slim only when a profile exists, the declarations were read and every one is accounted for; the first check that fails decides.
    ///
    /// `--stock` is checked first, and the declarations are then never read.
    public static func decide(
        stockRequested: Bool,
        runtimeIdentifier: String,
        osVersion: String,
        profileLookup: (String) -> ServiceProfile?,
        declarations: () -> Result<ProjectDeclarations, UnreadableDeclarations>
    ) -> BootMode {
        if stockRequested {
            return .stock(.requested)
        }
        guard let profile = profileLookup(runtimeIdentifier) else {
            return .stock(.noProfile(osVersion: osVersion))
        }
        switch declarations() {
        case let .failure(failure):
            return .stock(.unreadable(failure.reason))
        case let .success(found):
            let unmapped = found.unmapped
            if !unmapped.isEmpty {
                return .stock(.unmapped(unmapped))
            }
            return .slim(SlimBoot(profile: profile, plan: profile.plan(keeping: found.capabilities)))
        }
    }

    /// Whether the devices boot slim.
    public var isSlim: Bool {
        if case .slim = self {
            return true
        }
        return false
    }

    /// The devices line's account of the decision, without the line's own prefix.
    public var text: String {
        switch self {
        case let .stock(reason):
            return "stock: \(reason.text)"
        case let .slim(boot):
            let profile = boot.profile
            return "slim: \(boot.servicesOff) (iOS \(profile.runtime.version), profile v\(profile.profileVersion)), \(boot.keptText)"
        }
    }
}

extension SlimBoot {
    /// `93 of 338 services off`: the services the plan disables of those the profile lists.
    var servicesOff: String {
        "\(plan.disabled.count) of \(profile.services.count) services off"
    }

    /// `kept for the project: healthKit 5, iCloud 12`, or `nothing` where the project declares no capability.
    var keptText: String {
        let kept = plan.kept
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue) \($0.value.count)" }
            .joined(separator: ", ")
        return "kept for the project: \(kept.isEmpty ? "nothing" : kept)"
    }
}
