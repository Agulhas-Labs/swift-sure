//
// Copyright © Agulhas Labs
//

import Foundation

/// The note lines of one failed expectation kept for the close, how many bytes they hold, and whether ``RunFailureCensus/closestLineNoteLimit`` left the rest unread.
struct RunHeldNote {
    let index: Int
    var lines: [RunFailureCensus.NoteLine] = []
    var bytes = 0
    var truncated = false
}
