//
// Copyright © Agulhas Labs
//

/// The seven classes of `checkup` finding, declared in the order an answer lists them.
enum CheckupFindingClass: String, CaseIterable, Comparable, Sendable {
    case failed
    case callers
    case unproved
    case uncovered
    case exposed
    case flaky
    case duplicate

    /// The check whose evidence this class is read from.
    var check: CheckupCheck {
        switch self {
        case .failed, .unproved: .testRuns
        case .callers: .callers
        case .uncovered: .coverage
        case .exposed: .exposure
        case .flaky: .flakyTests
        case .duplicate: .duplicates
        }
    }

    /// Its place in the fixed order.
    private var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}
