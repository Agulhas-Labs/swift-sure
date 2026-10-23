//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorServices

/// The slim half of provisioning: the decision, the override written between a create and a boot, and the read-back after it.
///
/// **Nothing here fails the run.** A shard that did not come up slim is a value on the record, and the run goes on with it.
struct SlimProvisioning: Sendable {
    let environment: TestRunEnvironment
    let stockRequested: Bool
    let record: SlimBootRecord

    /// The clock the read's budget is measured on, in seconds; a test passes one it advances.
    var clock: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// Decides how this run boots, before anything is created, and records it.
    @discardableResult
    func decide(_ invocation: TestInvocation, resolution: ShardDevices.Resolution) -> BootMode {
        let mode = BootMode.decide(
            stockRequested: stockRequested,
            runtimeIdentifier: resolution.runtime,
            osVersion: resolution.osVersion,
            profileLookup: environment.serviceProfile,
            declarations: { declarations(of: invocation) }
        )
        record.decide(mode)
        return mode
    }

    /// Writes the plan's disabled services for each device, in shard order, and records a shard whose write failed as not slim.
    ///
    /// Each write goes through `unlessEnded`, which runs it under the run's own lock and skips it once a cancellation or the teardown has begun: a directory written for a device the teardown already deleted is one nothing would remove.
    func writeOverrides(to udids: [String], unlessEnded: (() -> Void) -> Void) {
        guard case let .slim(boot) = record.mode else {
            return
        }
        for (index, udid) in udids.enumerated() {
            unlessEnded {
                do {
                    try environment.overrides.write(boot.plan.disabled, for: udid)
                    record.wrote(boot.plan.disabled, forShard: index)
                } catch {
                    record.record(.notSlim("the override could not be written: \(error)"), forShard: index)
                }
            }
        }
    }

    /// Reads the booted device's disabled list back and records what it says, for a shard whose override was written.
    func readBack(shard index: Int, udid: String) {
        guard let written = record.written(forShard: index) else {
            return
        }
        record.record(outcome(of: written, udid: udid), forShard: index)
    }

    private func outcome(of written: [String], udid: String) -> ShardBoot {
        let output: Subprocess.Output
        do {
            output = try environment.simctl(SimulatorAccessibility.xcrunPath, ["simctl", "spawn", udid, "launchctl", "print-disabled", "system"])
        } catch {
            return .unverified("the read-back failed: \(error)")
        }
        guard output.succeeded else {
            if output.standardError.contains(Self.spawnTimeoutMarker) {
                return .unverified("the read-back timed out")
            }
            return .unverified("the read-back failed: \(ShardDevices.detail(of: output))")
        }
        let listed = DisabledServicesOverride.disabledLabels(fromPrintDisabled: output.standardOutput)
        let applied = written.filter(listed.contains).count
        guard applied == written.count else {
            return .notSlim("the runtime did not apply the override (\(applied) of \(written.count) read back)")
        }
        return .slim
    }

    private func declarations(of invocation: TestInvocation) -> Result<ProjectDeclarations, UnreadableDeclarations> {
        let budget = TestRunEnvironment.slimSettingsDeadline
        let started = clock()
        var attempt = read(invocation, within: budget)
        var first: String?
        var bound = budget
        if case let .failed(reason) = attempt {
            let left = budget - (clock() - started)
            if left >= Self.shortestRetry {
                bound = left
                first = reason
                attempt = read(invocation, within: left)
                if case .read = attempt {
                    record.noteRetriedRead(firstFailure: reason)
                }
            }
        }
        switch attempt {
        case let .failed(line):
            let earlier = first.flatMap { $0 == line ? nil : " (the first read failed: \($0))" } ?? ""
            return .failure(UnreadableDeclarations("the build settings could not be read: \(line)\(earlier)"))
        case .timedOut:
            let earlier = first.map { " (the first read failed: \($0))" } ?? ""
            return .failure(UnreadableDeclarations("the build settings read passed its \(Int(bound)) s bound\(earlier)"))
        case let .read(settings):
            let files = ProjectSettings.schemeFiles(container: invocation.container, scheme: invocation.scheme, inBuildSettings: settings.output)
            return ProjectSettings.declarations(inBuildSettings: settings.output, schemeFiles: files)
        }
    }

    private func read(_ invocation: TestInvocation, within bound: TimeInterval) -> Attempt {
        let settings: TestRunEnvironment.Launched
        do {
            settings = try environment.projectSettingsWithin(invocation.buildSettingsArguments, bound)
        } catch {
            return .failed(Self.errorLine(of: "\(error)"))
        }
        guard settings.exitCode == 0 else {
            if settings.answer.contains(Self.spawnTimeoutMarker) {
                return .timedOut
            }
            return .failed(Self.errorLine(of: settings.answer))
        }
        return .read(settings)
    }

    /// The least time left of the read's budget that a retry is worth starting for, in seconds.
    static var shortestRetry: TimeInterval {
        5
    }

    /// What `Subprocess` writes into the standard error of a spawn it ended at its deadline — the only text that says the bound was passed, where a tool's own "timed out" says something else.
    static var spawnTimeoutMarker: String {
        "the spawn timed out:"
    }

    /// The line that says why a read failed: the last that starts with `error:` in any case, else the first with `error:` in it in any case, else the first that is not `xcodebuild`'s own timestamped log line.
    static func errorLine(of text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let error = lines.last(where: { $0.lowercased().hasPrefix("error:") }) {
            return error
        }
        if let error = lines.first(where: { $0.lowercased().contains("error:") }) {
            return error
        }
        if let other = lines.first(where: { $0.range(of: logLinePattern, options: .regularExpression) == nil }) {
            return other
        }
        return lines.isEmpty ? "it printed nothing" : "it printed no error line"
    }

    private static var logLinePattern: String {
        #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)? xcodebuild\[\d+:\d+\]"#
    }
}

extension SlimProvisioning {
    /// What one build settings read came to: only a failed one, never a timed out one, is worth a second read.
    private enum Attempt {
        case read(TestRunEnvironment.Launched)
        case failed(String)
        case timedOut
    }
}
