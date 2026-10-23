//
// Copyright © Agulhas Labs
//

import Fieldwork
import SiftCore

extension InstallSummary {
    /// The summary `swift-sure install` prints: the lines its Cursor and Codex installers repeat on every run are said once, and the restart lines give way to each agent's next step.
    static var sift: InstallSummary {
        InstallSummary(
            tool: .sift,
            saidOnce: SiftCursorSetup.unsupported + [SiftCursorSetup.experimental] + CodexInstall.unsupported + [CodexHookInstaller.experimental],
            restarts: [CursorHookInstaller.restart, CodexHookInstaller.restart]
        )
    }
}
