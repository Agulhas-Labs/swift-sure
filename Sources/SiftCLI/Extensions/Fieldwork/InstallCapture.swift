//
// Copyright © Agulhas Labs
//

import Fieldwork
import SiftCore

extension InstallCapture {
    /// The sink to hand the installer.
    var output: CommandOutput {
        CommandOutput(
            keepsPartMarker: true,
            emit: { self.keep($0) },
            emitRaw: { self.keep(String(bytes: $0, encoding: .utf8) ?? "") },
            emitError: { self.keep($0) }
        )
    }
}
