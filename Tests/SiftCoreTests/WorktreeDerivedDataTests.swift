//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers where `swift-sure test` builds in a linked worktree: the chooser, the four command lines that carry its choice, and the answer line that names it.
@Suite(.temporaryDirectories)
struct WorktreeDerivedDataTests {
    private let derived = URL(fileURLWithPath: "/work/tree/.swift-sure/DerivedData")

    private func makeRun(passThrough: [String] = [], derivedDataPath: URL? = nil) throws -> TestInvocation {
        try TestInvocation(
            scheme: "TestDemo",
            deviceType: "iPhone 17",
            osVersion: "27.0",
            plan: "Default",
            only: ["TestDemo"],
            container: .project("TestDemo.xcodeproj"),
            passThrough: passThrough,
            derivedDataPath: derivedDataPath
        )
    }

    private let bundle = URL(fileURLWithPath: "/scratch/build.xcresult")
    private let flag = ["-derivedDataPath", "/work/tree/.swift-sure/DerivedData"]

    private func linkedWorktree() throws -> URL {
        let repo = try TestSources.makeTempRepo()
        return try TestSources.makeWorktree(of: repo, named: "wt")
    }

    @Test
    func theBuildCarriesTheChosenPathAheadOfThePassThrough() throws {
        let arguments = try makeRun(passThrough: ["-configuration", "Debug"], derivedDataPath: derived).buildForTestingArguments(resultBundle: bundle)

        #expect(Array(arguments.suffix(4)) == flag + ["-configuration", "Debug"])
        #expect(arguments.joined(separator: " ").contains("-resultBundlePath /scratch/build.xcresult -derivedDataPath /work/tree/.swift-sure/DerivedData -configuration Debug"))
    }

    @Test
    func theSettingsReadTheEnumerationAndAShardCarryTheChosenPath() throws {
        let run = try makeRun(passThrough: ["-skipPackagePluginValidation"], derivedDataPath: derived)

        let settings = run.buildSettingsArguments
        let enumeration = run.enumerationArguments(xctestrun: URL(fileURLWithPath: "/b/x.xctestrun"), outputPath: URL(fileURLWithPath: "/s/e.json"), resultBundle: bundle)
        let shard = run.shardArguments(xctestrun: URL(fileURLWithPath: "/b/x.xctestrun"), deviceUDID: "UDID", tests: [], resultBundle: bundle)

        #expect(settings.suffix(3) == ["-derivedDataPath", flag[1], "-skipPackagePluginValidation"])
        #expect(enumeration.suffix(2) == flag[...])
        #expect(shard.suffix(3) == ["-derivedDataPath", flag[1], "-skipPackagePluginValidation"])
    }

    @Test
    func noChosenPathLeavesEveryCommandLineAsItWas() throws {
        let run = try makeRun(passThrough: ["-skipPackagePluginValidation"])

        #expect(!run.buildForTestingArguments(resultBundle: bundle).contains("-derivedDataPath"))
        #expect(!run.buildSettingsArguments.contains("-derivedDataPath"))
        #expect(!run.enumerationArguments(xctestrun: bundle, outputPath: bundle, resultBundle: bundle).contains("-derivedDataPath"))
        #expect(!run.shardArguments(xctestrun: bundle, deviceUDID: "U", tests: [], resultBundle: bundle).contains("-derivedDataPath"))
        #expect(run.derivedDataPassThrough == ["-skipPackagePluginValidation"])
    }

    @Test
    func theProductsLookupFollowsTheChosenPath() throws {
        let run = try makeRun(passThrough: ["-skipPackagePluginValidation"], derivedDataPath: derived)

        let products = try PackageProductsDirectory.resolve(
            workingDirectory: URL(fileURLWithPath: "/work/tree"),
            passThrough: run.derivedDataPassThrough,
            derivedDataRoot: URL(fileURLWithPath: "/nowhere")
        )

        #expect(products == "/work/tree/.swift-sure/DerivedData/Build/Products")
    }

    @Test
    func aLinkedWorktreeGetsItsOwnDerivedDataAndTheCacheIsExcluded() throws {
        let worktree = try linkedWorktree()

        let chosen = WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: ["-skipPackagePluginValidation"])

        #expect(chosen?.path == worktree.appendingPathComponent(".swift-sure/DerivedData").path)
        let common = try #require(GitContext.commonDirectory(of: worktree))
        let exclude = try String(contentsOf: common.appendingPathComponent("info/exclude"), encoding: .utf8)
        #expect(exclude.contains(".swift-sure/"))
    }

    @Test
    func theChosenDirectoryIgnoresItsOwnContentsAndKeepsAFileAlreadyThere() throws {
        let worktree = try linkedWorktree()
        let file = worktree.appendingPathComponent(".swift-sure/DerivedData/.gitignore")

        _ = WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: [])

        #expect(try String(contentsOf: file, encoding: .utf8) == "*\n")

        try Data("mine\n".utf8).write(to: file)
        _ = WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: [])
        #expect(try String(contentsOf: file, encoding: .utf8) == "mine\n")
    }

    @Test
    func aCallersOwnDerivedDataPathWins() throws {
        let worktree = try linkedWorktree()

        #expect(WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: ["-derivedDataPath", "build"]) == nil)
    }

    @Test
    func thePrimaryCheckoutAndADirectoryInNoRepositoryChooseNothing() throws {
        let repo = try TestSources.makeTempRepo()
        let outside = try TemporaryDirectory.make("outside")

        #expect(WorktreeDerivedData.chosen(repositoryRoot: repo, passThrough: []) == nil)
        #expect(WorktreeDerivedData.chosen(repositoryRoot: outside, passThrough: []) == nil)
    }

    @Test
    func theAnswerNamesTheDirectoryOnlyWhenSiftChoseIt() {
        let counts = ShardReconciliation.Counts(expected: 0, ran: 0, passed: 0, failed: 0, skipped: 0, missing: 0, duplicated: 0)
        let reconciliation = ShardReconciliation(
            counts: counts, shards: [], missing: [], shortfalls: [], duplicated: [],
            failed: [], timings: [], failures: [], notes: []
        )
        let plan = ShardPlan(shards: [], requestedShards: 1, overheadSeconds: 0, estimatedTests: 0, estimatedSeconds: 0, lowering: nil)

        let named = ShardAnswerRenderer(derivedDataLine: WorktreeDerivedData.line(for: derived), devicesLine: "devices line").render(reconciliation, plan: plan)
        let silent = ShardAnswerRenderer(devicesLine: "devices line").render(reconciliation, plan: plan)

        #expect(named.hasSuffix("devices line\nderived data .swift-sure/DerivedData — inside this worktree, so it goes when the worktree is removed"))
        #expect(!silent.contains("derived data"))
    }
}
