//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// A selector word holding a space reached the tool as one argument, and is said to be, not blamed on a missing `()`.
struct RunTestSelectorUnsplitHintTests {
    @Test
    func anUnsplitOnlyTestingWordIsSaidToBeOneArgument() throws {
        let selector = try #require(RunTestSelector.named(in: [
            "xcodebuild", "test", "-only-testing:GizmoTests/GizmoTests/a -only-testing:GizmoTests/GizmoTests/b",
        ]))
        let headline = selector.headline(label: "xcodebuild")

        #expect(headline.contains("one argument with a space in it"))
        #expect(headline.contains("zsh does not split"))
        #expect(!headline.contains("trailing ()"))
    }

    @Test
    func anUnsplitFilterWordIsSaidToBeOneArgument() throws {
        let selector = try #require(RunTestSelector.named(in: ["swift", "test", "--filter", "A B"]))
        let headline = selector.headline(label: "swift test")

        #expect(headline.contains("one argument with a space in it"))
        #expect(!headline.contains("trailing ()"))
    }

    @Test
    func aSplitSelectorKeepsTheParenthesesHint() throws {
        let selector = try #require(RunTestSelector.named(in: ["xcodebuild", "test", "-only-testing:GizmoTests/GizmoTests/a"]))
        let headline = selector.headline(label: "xcodebuild")

        #expect(headline.contains("trailing (): -only-testing:GizmoTests/GizmoTests/a()"))
        #expect(!headline.contains("one argument"))
    }

    @Test
    func theHintIsWithheldOnlyFromTheWordWithTheSpace() throws {
        let selector = try #require(RunTestSelector.named(in: [
            "xcodebuild", "test", "-only-testing:GizmoTests/GizmoTests/a -only-testing:GizmoTests/GizmoTests/b",
            "-only-testing:GizmoTests/GizmoTests/c",
        ]))
        let headline = selector.headline(label: "xcodebuild")

        #expect(headline.contains("one argument with a space in it"))
        #expect(headline.contains("trailing (): -only-testing:GizmoTests/GizmoTests/c()"))
        #expect(!headline.contains("GizmoTests/b()"))
    }
}
