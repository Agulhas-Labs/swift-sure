//
// Copyright © Agulhas Labs
//

import Foundation

/// Everything one sharded test run is asked for, in one value, so the invocation, the ledger, the watcher and the planner all read the same request.
public struct TestRunRequest: Sendable {
    /// The scheme to build and run.
    public let scheme: String

    /// The device *type* as `simctl list devicetypes` spells it, which names both what is created and what the one build is made for.
    public let deviceTypeName: String

    /// The runtime version asked for, or `nil` for the newest installed one that runs the device type.
    public let osVersion: String?

    /// The test plans the caller named, in the order named: one is a single-plan run, several are run from one build.
    public let plans: [String]

    /// Whether the run covers every test plan of the scheme, from one build.
    public let allPlans: Bool

    /// The test plan, when the caller named exactly one.
    public var plan: String? {
        plans.count == 1 && !allPlans ? plans.first : nil
    }

    /// Whether the run covers more than one plan, each on the same pool of devices.
    public var isMultiPlan: Bool {
        allPlans || plans.count > 1
    }

    /// `--only` values, in the `Target` / `Target/Class` / `Target/Class/test` spellings.
    public let only: [String]

    /// `--skip` values, in the same spellings.
    public let skip: [String]

    /// The project or workspace the scheme lives in, when the caller named one.
    public let container: TestInvocation.Container?

    /// Everything after `--`, handed to `xcodebuild` untouched.
    public let passThrough: [String]

    /// The derived data directory `swift-sure` chose for a linked worktree's build (``WorktreeDerivedData/chosen(repositoryRoot:passThrough:)``), or `nil`.
    public let derivedDataPath: URL?

    /// The shards the caller asked for, or `nil` to take the host's own count.
    public let requestedShards: Int?

    /// The floor `--shard-timeout` sets under a shard's bound, or `nil` for the built-in hour.
    public let shardTimeoutSeconds: TimeInterval?

    /// Where the caller ran the command, which is where every wrapped `xcodebuild` is started.
    public let workingDirectory: URL

    /// The repository whose `.swift-sure/` holds the ledger, the durations and the run logs.
    public let repositoryRoot: URL

    /// The running `swift-sure`, which is what the watcher is started from — a detached copy of this binary is the only thing that can finish the cleanup after a kill.
    public let executable: URL

    /// Whether every shard boots stock, with no simulator services switched off and the build settings never read for it.
    public let stock: Bool

    /// Whether animations stay on in the app under UI test, so the build's `.xctestrun` runs as it was written and no library is inserted to switch them off.
    public let animations: Bool

    public init(
        scheme: String,
        deviceTypeName: String,
        osVersion: String? = nil,
        plan: String? = nil,
        plans: [String] = [],
        allPlans: Bool = false,
        only: [String] = [],
        skip: [String] = [],
        container: TestInvocation.Container? = nil,
        passThrough: [String] = [],
        derivedDataPath: URL? = nil,
        requestedShards: Int? = nil,
        shardTimeoutSeconds: TimeInterval? = nil,
        workingDirectory: URL,
        repositoryRoot: URL,
        executable: URL,
        stock: Bool = false,
        animations: Bool = false
    ) {
        self.scheme = scheme
        self.deviceTypeName = deviceTypeName
        self.osVersion = osVersion
        self.plans = TestRun.unique((plan.map { [$0] } ?? []) + plans)
        self.allPlans = allPlans
        self.only = only
        self.skip = skip
        self.container = container
        self.passThrough = passThrough
        self.derivedDataPath = derivedDataPath
        self.requestedShards = requestedShards
        self.shardTimeoutSeconds = shardTimeoutSeconds
        self.workingDirectory = workingDirectory
        self.repositoryRoot = repositoryRoot
        self.executable = executable
        self.stock = stock
        self.animations = animations
    }
}

extension TestRunRequest {
    /// The `swift-sure test` invocation that reproduces this run's scheme, device, OS, plan and container — everything a re-run needs before `--shards 1` and the failing `--only` arguments are appended.
    var rerunCommandPrefix: String {
        rerunCommandPrefix(plans: plans, allPlans: allPlans)
    }

    /// ``rerunCommandPrefix`` naming `plans` and `allPlans` in place of the request's own: a multi-plan run's re-run names only the plans that failed.
    func rerunCommandPrefix(plans: [String], allPlans: Bool) -> String {
        var words = [ProductName.current.binary, "test", "--scheme", Self.shellQuoted(scheme), "--device", Self.shellQuoted(deviceTypeName)]
        if let osVersion {
            words += ["--os", Self.shellQuoted(osVersion)]
        }
        for plan in plans {
            words += ["--plan", Self.shellQuoted(plan)]
        }
        if allPlans {
            words.append("--all-plans")
        }
        switch container {
        case let .project(path):
            words += ["--project", Self.shellQuoted(path)]
        case let .workspace(path):
            words += ["--workspace", Self.shellQuoted(path)]
        case nil:
            break
        }
        if stock {
            words.append("--stock")
        }
        if animations {
            words.append("--animations")
        }
        return words.joined(separator: " ")
    }

    /// The caller's pass-through as the tail of a re-run line, ` -- <words>`, or `nil` where there was none.
    var rerunCommandSuffix: String? {
        passThrough.isEmpty ? nil : " -- " + passThrough.map(Self.shellQuoted).joined(separator: " ")
    }

    /// A value as one shell word: itself, unquoted, when it holds nothing the shell would split or expand, else itself in single quotes with any single quote of its own escaped — so a printed command is safe to paste and run rather than a claim the reader has to repair first.
    static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./-"))
        guard !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) else {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return value
    }
}
