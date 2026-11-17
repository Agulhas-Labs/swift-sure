//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the rule that the filtered-run line says "did not run" only of a suite that could have run: one compiled out on this platform is neither counted nor named.
@Suite(.serialized, .temporaryDirectories)
struct FilteredRunReachCompiledOutTests {
    private static func checkout() async throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Lib\",\n    targets: [\n        .target(name: \"Lib\"),\n        .testTarget(name: \"LibTests\", dependencies: [\"Lib\"]),\n    ]\n)\n", to: "Package.swift", in: root)
        try TestSources.write("public struct Widget {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.write(FilteredRunReachHintTests.xctestSource("WidgetTests", ["testA", "testB", "testGamma"]), to: "Tests/LibTests/WidgetTests.swift", in: root)
        let gadget = FilteredRunReachHintTests.xctestSource("GadgetTests", ["testDoubling", "testExample"])
        try TestSources.write("#if os(Linux)\n" + gadget + "#endif\n", to: "Tests/LibTests/GadgetTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try await SiftEngine(directory: root).ensureFresh()
        try TestSources.write("public struct Widget {\n    public init() {}\n    public var size = 1\n}\n", to: "Sources/Lib/Core.swift", in: root)
        return root
    }

    @Test
    func aSuiteCompiledOutOnThisPlatformIsNeitherCountedNorNamed() async throws {
        let root = try await Self.checkout()
        let lines = try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root)

        #expect(lines.isEmpty, "\(lines)")
    }
}
