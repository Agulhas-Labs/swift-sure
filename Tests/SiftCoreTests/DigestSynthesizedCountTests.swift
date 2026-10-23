//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The opening line of a served overload set counts what follows it: where the compiler's memberwise initializer is served beside the declared ones, the line says so.
@Suite(.temporaryDirectories)
struct DigestSynthesizedCountTests {
    private static var source: String {
        """
        struct Gizmo {
            var left: Int
            var right: Int
        }

        extension Gizmo {
            init(both: Int) {
                self.init(left: both, right: both)
            }

            init(zero: Bool) {
                self.init(left: 0, right: 0)
            }
        }

        struct Orchard {
            var size: Int
            init(size: Int) {
                self.size = size
            }

            init(zero: Bool) {
                self.size = 0
            }
        }
        """
    }

    private static func opening(of target: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> (line: String, answer: String) {
        let engine = try await TestSources.engine(files: ["Sources/App/Shapes.swift": source])
        let answer = try engine.digest(target: target, options: DigestOptions())
        let line = try #require(answer.components(separatedBy: "\n").first { $0.contains("names 2 declarations") }, "\(answer)", sourceLocation: sourceLocation)
        return (line, answer)
    }

    @Test
    func theOpeningLineCountsTheSynthesizedInitServedBesideTheDeclaredOnes() async throws {
        let (line, answer) = try await Self.opening(of: "Gizmo.init")

        #expect(line == "Gizmo.init names 2 declarations, 6 lines together, + the synthesized memberwise init; each follows", "\(answer)")
        #expect(answer.contains("compiler-synthesized"), "\(answer)")
    }

    @Test
    func theOpeningLineAddsNothingWhereTheCompilerWritesNoInit() async throws {
        let (line, answer) = try await Self.opening(of: "Orchard.init")

        #expect(line == "Orchard.init names 2 declarations, 6 lines together; each follows", "\(answer)")
        #expect(!answer.contains("compiler-synthesized"), "\(answer)")
    }
}
