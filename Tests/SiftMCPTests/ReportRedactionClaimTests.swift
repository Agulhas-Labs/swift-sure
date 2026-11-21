//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// `audit` and `flakes` pseudonymise by default; the `report` page does not, and no document or help text may tell a reader it is safe to share.
struct ReportRedactionClaimTests {
    /// The shipped documents that describe redaction.
    static let documents = ["Distribution/INSTALL.md", "Docs/Guide.md", "Docs/Design.md"]

    /// No sentence that names `report` beside pseudonymisation reads as if the page were pseudonymised: each one says it is not.
    @Test(arguments: documents)
    func noDocumentSaysTheReportPageIsPseudonymised(path: String) throws {
        let text = try Self.words(String(contentsOf: GuideCommandReferenceTests.repositoryRoot.appendingPathComponent(path), encoding: .utf8))
        let offending = Self.sentences(of: text).filter { sentence in
            sentence.contains("`report`") && sentence.contains("pseudonymised") && !sentence.contains("not redacted")
        }

        #expect(offending.isEmpty, "\(path) says or implies `report` is pseudonymised: \(offending)")
    }

    /// Each document that teaches redaction also says, in so many words, that the `report` page is not redacted.
    @Test(arguments: documents)
    func everyDocumentSaysTheReportPageIsNotRedacted(path: String) throws {
        let text = try Self.words(String(contentsOf: GuideCommandReferenceTests.repositoryRoot.appendingPathComponent(path), encoding: .utf8))

        #expect(text.contains("is not redacted"), "\(path) never says the `report` page is not redacted")
    }

    /// `report --help` says the page is not redacted, and `report` has no `--unredact` for the documents to point at.
    @Test
    func theReportHelpSaysThePageIsNotRedacted() {
        let help = ReportCommand.helpMessage()

        #expect(Self.words(ReportCommand.configuration.discussion).contains(ReportCommand.notRedacted))
        #expect(!help.contains("--unredact"))
    }

    /// The `run-output` topic's `flakes` paragraph no longer groups `report` with the pseudonymised reports.
    @Test
    func theFlakesParagraphDoesNotGroupTheReportWithTheRedactedOnes() throws {
        let body = try Self.words(#require(HelpTopics.topic(named: "run-output")).body)

        #expect(!body.contains("as `report` and `audit` are"))
        #expect(body.contains("the `report` page is not redacted"))
    }

    /// `text` with every run of whitespace, line breaks included, reduced to one space.
    static func words(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `text` cut into sentences at a full stop, semicolon or colon followed by a space.
    static func sentences(of text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character == " ", let mark = previous, ".;:".contains(mark) {
                sentences.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        sentences.append(current)
        return sentences
    }
}
