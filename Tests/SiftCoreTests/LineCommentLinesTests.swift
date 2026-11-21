//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `LineCommentLines`: only a line whose sole token is a line comment counts, as the lexer reads the whole file.
struct LineCommentLinesTests {
    @Test
    func `plain and doc line comments count, indented by spaces or a tab`() {
        let source = "// a\n/// b\n    // c\n\t// d\nlet widget = 1\n"

        #expect(LineCommentLines.of(source: source) == [1, 2, 3, 4])
    }

    @Test
    func `a trailing comment after code is not a comment line`() {
        #expect(LineCommentLines.of(source: "let gizmo = 1 // trailing\n// own\n") == [2])
    }

    @Test
    func `a slash slash line inside a multi-line string is code`() {
        let source = "let text = \"\"\"\n// inside\n/// also inside\n\"\"\"\n// outside\n"

        #expect(LineCommentLines.of(source: source) == [5])
    }

    @Test
    func `a slash slash line inside a block comment is not a comment line`() {
        let source = "/*\n// inside\n*/\n// outside\n"

        #expect(LineCommentLines.of(source: source) == [4])
    }

    @Test
    func `a comment on the last line with no newline counts`() {
        #expect(LineCommentLines.of(source: "let a = 1\n// end") == [2])
    }
}
