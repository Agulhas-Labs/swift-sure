//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Attributes are written with their `@`, and the index holds them without it; `attr:@Name` once matched nothing.
struct SearchAttrAtSignTests {
    private static var text: String {
        """
        @Gizmo struct Widget {}

        struct Plain {
            @Gizmo func spin() {}
            @Sprocket func turn() {}
        }
        """
    }

    private static func found(_ query: String) throws -> [String] {
        let parsed = try StructuralQuery(query)
        return StructuralMatcher.matches(in: text, path: "Sources/Widget.swift", query: parsed)
            .map { String($0.qualifiedName.prefix { $0 != "(" }) }
            .sorted()
    }

    @Test func `a leading at sign on an attr value matches what the bare name matches`() throws {
        let bare = try Self.found("attr:Gizmo")

        #expect(bare == ["Plain.spin", "Widget"])
        #expect(try Self.found("attr:@Gizmo") == bare)
        #expect(try Self.found("attr:@Gizmo|@Sprocket") == ["Plain.spin", "Plain.turn", "Widget"])
        #expect(try Self.found("kind:func !attr:@Gizmo") == ["Plain.turn"])
    }
}
