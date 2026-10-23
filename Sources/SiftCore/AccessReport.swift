//
// Copyright © Agulhas Labs
//

/// `diff`'s access section as gathered: the declarations looked up, those never judged, and those past the lookup budget.
struct AccessReport: Sendable {
    var findings: [AccessFinding] = []
    var notJudged: [AccessExclusion: Int] = [:]
    var notChecked = 0
}
