//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A range refusal spells the command that reads the range, and `diff`'s own spelling is the default.
@Suite(.temporaryDirectories)
struct DiffRangeCommandNameTests {
    private static func message(_ argument: String, command: String?, in root: URL) -> String? {
        do {
            if let command {
                _ = try DiffRange.resolve(argument, git: GitContext(repoRoot: root), command: command)
            } else {
                _ = try DiffRange.resolve(argument, git: GitContext(repoRoot: root))
            }
            return nil
        } catch {
            return (error as? DiffRange.Refusal)?.message
        }
    }

    @Test
    func everyRefusalNamesTheCommandItWasGiven() throws {
        let root = try TestSources.makeTempRepo()
        let binary = ProductName.current.binary

        for argument in ["HEAD~1..", "..HEAD", "main..nonexistent", "nonexistent", "^!"] {
            let message = try #require(Self.message(argument, command: "checkup", in: root), "\(argument)")
            #expect(message.hasPrefix("\(binary) checkup: ") || message.contains("`\(binary) checkup"), "\(argument)")
            #expect(!message.contains("\(binary) diff"), "\(argument)")
        }
    }

    @Test
    func theDefaultCommandIsDiff() throws {
        let root = try TestSources.makeTempRepo()
        let binary = ProductName.current.binary

        for argument in ["HEAD~1..", "nonexistent", "^!"] {
            let defaulted = try #require(Self.message(argument, command: nil, in: root), "\(argument)")
            let named = try #require(Self.message(argument, command: "diff", in: root), "\(argument)")
            #expect(defaulted == named, "\(argument)")
            #expect(defaulted.contains("\(binary) diff"), "\(argument)")
        }
    }
}
