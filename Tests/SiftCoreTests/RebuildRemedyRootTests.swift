//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The rebuild commands an existing store's answers print name the root when run from another directory would build the caller's checkout.
struct RebuildRemedyRootTests {
    private static var flag: String {
        "--root /Users/Shared/some-checkout "
    }

    @Test func aStaleRefusalNamesTheRoot() {
        let rebuild = SemanticRefusal.Rebuild.swiftPM(buildTests: true, package: "Kit", rootFlag: Self.flag)

        #expect(SemanticRefusal.Reason.modifiedSinceBuild.instruction(rebuild: rebuild)
            == "; rebuild with `swift-sure run \(Self.flag)-- swift build --package-path Kit --build-tests`, then retry")
        #expect(SemanticRefusal.Reason.noCoveringUnit.instruction(rebuild: rebuild).contains("`swift-sure run \(Self.flag)-- swift build --package-path Kit --build-tests`"))
    }

    @Test func aRebuildFromTheRootStaysPlain() {
        let rebuild = SemanticRefusal.Rebuild.swiftPM(buildTests: false, package: "")

        #expect(SemanticRefusal.Reason.modifiedSinceBuild.instruction(rebuild: rebuild) == "; rebuild with `swift-sure run -- swift build`, then retry")
    }

    @Test func unbuiltTestFilesNameTheRoot() {
        let coverage = TestFileCoverage(withoutUnit: 2, neverBuilt: true, provenance: .swiftPMBuild, rootFlag: Self.flag)

        #expect(coverage.build == "build with `swift-sure run \(Self.flag)-- swift build --build-tests`")
    }
}
