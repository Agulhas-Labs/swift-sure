//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

struct AuditCursorNote {
    /// The line that says Cursor's sessions were not read, when SwiftSure's hooks are registered in `cursorDirectory`'s `hooks.json`; `nil` when there is no such directory, file or entry of SwiftSure's, or the file cannot be read or parsed.
    static func text(cursorDirectory: URL?, projectsDirectory: URL, unredacted: Bool) -> String? {
        guard let cursorDirectory,
              let data = try? SiftCursorSetup.read(cursorDirectory.appendingPathComponent(CursorHooksFile.fileName)),
              SiftCursorSetup.registersAHook(in: data)
        else { return nil }
        let path = unredacted ? projectsDirectory.path : Redactor.tilded(projectsDirectory.path)
        return "not read: Cursor's sessions — \(ProductName.current.binary) audit reads Claude Code's transcripts (\(path)) only"
    }
}
