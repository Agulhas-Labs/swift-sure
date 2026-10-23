//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// Why every shard boots stock.
public enum StockReason: Sendable, Equatable {
    case requested
    case noProfile(osVersion: String)
    case unreadable(String)
    case unmapped([String])

    /// The reason in the words the devices line prints after `stock: `.
    public var text: String {
        switch self {
        case .requested:
            "--stock"
        case let .noProfile(osVersion):
            "no service profile for iOS \(osVersion)"
        case let .unreadable(reason):
            "the project's declarations could not be read (\(reason))"
        case let .unmapped(names):
            "the project declares what no rule maps (\(names.joined(separator: ", ")))"
        }
    }
}
