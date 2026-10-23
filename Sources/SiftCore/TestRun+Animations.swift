//
// Copyright © Agulhas Labs
//

import Foundation

/// Which `.xctestrun` a run uses, and the line saying whether animations are off in the app under UI test.
struct AnimationsDecision {
    let xctestrun: URL
    let note: String?
}

extension TestRun {
    /// The copy with animations off where the seam makes one, or the original: with `--animations`, with no UI target, or where the copy could not be made, which is then said.
    static func animationsDecision(for original: URL, in ledger: ShardLedger, request: Request, environment: Environment) -> AnimationsDecision {
        guard !request.animations else {
            return AnimationsDecision(xctestrun: original, note: nil)
        }
        do {
            guard let copy = try environment.xctestrunWithAnimationsOff(original, ledger.directory) else {
                return AnimationsDecision(xctestrun: original, note: nil)
            }
            return AnimationsDecision(xctestrun: copy, note: TestRun.animationsOffNote)
        } catch {
            let detail = (error as? AnimationsOffError).map(\.description) ?? error.localizedDescription
            return AnimationsDecision(xctestrun: original, note: "animations: on, since the library that switches them off could not be used: \(detail)")
        }
    }

    static var animationsOffNote: String {
        "animations: UIKit off in the app under UI test (SwiftUI animations still run); a test keeps them with launchEnvironment \(EnvironmentVariable.animations.name)=on, a run with --animations"
    }
}
