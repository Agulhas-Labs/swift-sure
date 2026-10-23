//
// Copyright © Agulhas Labs
//

import ArgumentParser
@testable import SiftCLI
import Testing

/// `--purge` deletes the `.bak-swift-sure` backups the uninstall lists as well as the `.swift-sure/` directories, so its help says both.
struct UninstallPurgeHelpTests {
    /// The flag's own help, the line a reader deciding whether to pass it sees, names the backups and whose they are.
    @Test
    func thePurgeHelpNamesTheBackupsItDeletes() {
        let help = UninstallCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")

        #expect(help.contains("Also delete every listed .swift-sure/ directory"), "\(help)")
        #expect(help.contains("every listed *.bak-swift-sure backup (of settings.json, Cursor's mcp.json and hooks.json, and Codex's hooks.json)"), "\(help)")
    }
}
