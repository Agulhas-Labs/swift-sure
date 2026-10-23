//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// The release script's stamps, read from its text: running it means a release build, so these pin the lines that decide the stamp's length and what its date is called.
struct MakeDistStampTests {
    private static let commands: [String] = {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent() // SiftCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // the repository root
        let script = (try? String(contentsOf: repository.appending(path: "Distribution/make-dist.sh"), encoding: .utf8)) ?? ""
        return script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("#") }
    }()

    /// A public commit is cut to eight characters, and the tree stamp is abbreviated to the same eight.
    @Test
    func bothStampsAreEightCharactersLong() {
        #expect(Self.commands.contains { $0.contains("cut -c1-8") })
        #expect(Self.commands.contains { $0.contains("git rev-parse 'HEAD^{tree}' | cut -c1-8") })
        #expect(!Self.commands.contains { $0.contains("git rev-parse --short") })
    }

    /// The date beside a public commit is labelled as the source's, since it is not that commit's own.
    @Test
    func aPublicCommitsDateIsLabelledAsTheSources() {
        #expect(Self.commands.contains { $0.contains(#"DATE_FORM=", source dated %s""#) })
        #expect(Self.commands.contains { $0.contains(#"DATE_FORM=" (%s)""#) })
        #expect(Self.commands.contains { $0.contains(#"$STAMP_LABEL \`$STAMP\`$DATE_TEXT, built"#) })
    }
}
