//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The simulator preference an in-process accessibility suite depends on, which every UI-test session switches off as it ends — and which a wrapped test run switches back on.
///
/// **A test run that leaves the device worse than it found it is a run that breaks the next one.** When a UI-test session ends, the test manager's teardown stores both `AccessibilityEnabled` and `ApplicationAccessibilityEnabled` as off on that device, within milliseconds of `xcodebuild` returning. It is one write per session, not a stream of them. `AccessibilityEnabled` is the key that decides whether a hosted view builds accessibility elements at all, so the *next* package run on the same simulator fails every test that reads one — hundreds of them, failing in a way that looks exactly like a code defect in code the UI suite never touched. Measured in a consuming project on 16 Sep 2026: 466 failures in 3068 tests straight after the UI suite, and 3068 passing after re-arming the preference.
///
/// **Read and written through the runtime's own `defaults`, never `/usr/bin/defaults`.** `simctl spawn` runs an absolute path from the host, so the absolute spelling is the host's own tool looking for a domain the simulator keeps in its own preference daemon: it writes nowhere the simulator reads, and reports that the domain does not exist. The bare name is resolved inside the runtime's root, which is why it is the one spelling that works.
///
/// **A write is only made over a preference seen off.** `swift-sure run` returns after `xcodebuild` has exited, so a teardown has already landed by the time this reads; a key that reads on stays unwritten, and the run pays one short poll rather than a write and its confirmation.
///
/// **Every spawn's wait is bounded, so no restore can hold up the run it follows.** What is bounded is how long `swift-sure run` waits, not the lifetime of everything a spawn started: the child itself is ended at the deadline, but the `defaults` that `simctl spawn` starts runs under CoreSimulator rather than as a descendant of the child, so no signal sent from here — to the child or to its process group — reaches it, and one that wedged is left to the service that owns it. A wedged simulator or a hung `CoreSimulator` service would otherwise block `swift-sure run` forever *after* the wrapped command has already exited, and the exit code the caller is waiting on would never arrive. Each spawn gets ``Subprocess/defaultDeadline`` seconds of wall clock and is then ended — `SIGTERM`, then `SIGKILL` a moment later — and reports that it timed out, which the state machine reads as a failed read or a failed write like any other. Both waits above are clocks rather than counts of spawns, so the worst case for one device is its own budget plus the one spawn that was in flight when the budget ran out: at most about seven seconds in the poll (two seconds of budget and a five-second read) and about twenty-eight in the write loop (ten seconds of budget and a last round of two writes, the 2.5s confirmation delay and a read) — **about 35 seconds for a device whose every spawn wedges**, against a hang with no end at all before it. A run naming several simulators pays that per device, one after another.
public struct SimulatorAccessibility {
    /// The preference domain the simulator keeps it in.
    public static var domain: String {
        "com.apple.Accessibility"
    }

    /// The key a hosted view consults before it builds accessibility elements, measured rather than assumed.
    public static var key: String {
        "AccessibilityEnabled"
    }

    /// Every key the session teardown switches off, in the order a restore puts them back — the deciding one first.
    ///
    /// The second is restored as well although nothing here needs it, because the teardown took it in the same call and a restore that put back half of what was taken would leave the device other than it found it.
    public static var keys: [String] {
        [key, "ApplicationAccessibilityEnabled"]
    }

    /// Re-arms the preference for every simulator `arguments` ran its tests on, in the order argv names them — and is empty where this invocation put no test run on a simulator.
    ///
    /// Whatever the run's exit code: a UI suite that failed tore its session down exactly as a green one does.
    ///
    /// **Every simulator destination on the command line, not just the first.** An invocation may carry several, and each one's session tears its own device down; restoring one of them and reading as a success would leave the rest off while the answer said the run was clean. They are restored one after another, in the order they were written, and each one gets its own line of the answer.
    ///
    /// - Parameters:
    ///   - arguments: the wrapped command, executable first — the same array recognition and the verdict contract read.
    ///   - log: the run's own transcript, read only when `arguments` carries no `-destination` at all — the one place a default destination Xcode resolved for itself shows.
    ///   - run: spawns a child and returns what it said; a script in a test, so nothing here spawns `simctl` under the suite.
    ///   - pause: waits, between two reads of the preference and before confirming a write.
    ///   - now: the clock both waits are bounded by, so a device whose preference never moves costs the budget rather than however many spawns fit in it.
    public static func restore(
        after arguments: [String],
        log: String? = nil,
        run: (String, [String]) throws -> Subprocess.Output = { try Subprocess.run($0, $1) },
        pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        now: () -> Date = { Date() }
    ) -> [Restoration] {
        SimulatorDestination.simulatorsOfTestRun(arguments, log: log).map { destination in
            switch destination {
            case let .identified(udid):
                restore(udid: udid, run: run, pause: pause, now: now)
            case let .named(name, osVersion):
                if let udid = resolve(name: name, osVersion: osVersion, run: run) {
                    restore(udid: udid, run: run, pause: pause, now: now)
                } else {
                    Restoration(udid: nil, state: .undetermined(reason: "no single available simulator is named \(name)\(osVersion.map { " on OS \($0)" } ?? "")"))
                }
            case .unnamed:
                Restoration(udid: nil, state: .undetermined(reason: "the run named no device — a simulator platform with no device on it, or no -destination at all — so there is nothing to read the preference from; name the device with -destination id=<udid> to have it checked"))
            }
        }
    }

    /// The warnings owed before a test run starts, one for each simulator the command names outright whose preference reads off.
    ///
    /// **Only an `id=` destination, and only a plain read.** A named destination needs a listing to settle which device it is, and the run has not chosen yet; a read that fails says nothing, since the after-run check is the one that answers for a device it cannot reach. Nothing is written and nothing is rebooted: the line says what to do, and the run goes on as it would have.
    public static func warnings(
        before arguments: [String],
        run: (String, [String]) throws -> Subprocess.Output = { try Subprocess.run($0, $1) }
    ) -> [String] {
        SimulatorDestination.simulatorsOfTestRun(arguments).compactMap { destination in
            guard case let .identified(udid) = destination, case let .value(value) = read(udid: udid, run: run), value == offValue else {
                return nil
            }
            return "accessibility: off on \(udid) — the first launch will draw an empty tree; arm it and reboot the simulator first"
        }
    }

    /// Switches the preference back on for one device, and says what it did.
    ///
    /// The first read decides everything. Off is the teardown's own write, so both keys go back on and the write is confirmed a few seconds later — seeing a write land is not seeing it hold, and a late teardown is the case that tells them apart. On, still on after the short poll, is a device nothing has to be done to. A read that fails is one of three different things and is answered as whichever it is — see ``Restoration/State``.
    public static func restore(
        udid: String,
        run: (String, [String]) throws -> Subprocess.Output,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Restoration {
        switch waitForTeardown(udid: udid, run: run, pause: pause, now: now) {
        case let .value(value) where value == offValue:
            write(udid: udid, knownOff: true, run: run, pause: pause, now: now)
        case .value:
            Restoration(udid: udid, state: .alreadyOn)
        case .never:
            Restoration(udid: udid, state: .neverSwitchedOff)
        case let .unreachable(reason):
            Restoration(udid: udid, state: .unreached(reason: reason))
        case let .unreadable(reason):
            Restoration(udid: udid, state: .unconfirmed(reason: reason))
        }
    }

    /// The one qualification a run's headline carries for however many devices it acted on: the worst of them.
    ///
    /// The worst, because the headline is one line and a run that left one device off is a run a reader has to act on whatever the others did — and a qualification is dropped only where *every* device is known fit. `nil` for a run that named no simulator at all.
    public static func qualification(of restorations: [Restoration]) -> String? {
        restorations.max { $0.severity < $1.severity }?.qualification
    }

    /// The `simctl` argument vectors that switch the preference back on for a device, one per key.
    ///
    /// **`defaults`, never `/usr/bin/defaults`**: `simctl spawn` runs an absolute path from the host, so the absolute spelling writes nowhere the simulator reads.
    public static func enableArguments(udid: String) -> [[String]] {
        keys.map { enableArguments(udid: udid, key: $0) }
    }

    /// The `simctl` argument vector that reads the deciding key through the runtime's own preference daemon.
    public static func readArguments(udid: String) -> [String] {
        ["simctl", "spawn", udid, runtimeDefaults, "read", domain, key]
    }

    /// The commands a person runs to do what a restore does, for the case where the restore could not.
    ///
    /// Generated from ``enableArguments(udid:)``, so the instruction cannot drift from what the tool itself would have run. A device this could not name is spelled with the placeholder the reader substitutes.
    public static func command(udid: String?) -> String {
        enableArguments(udid: udid ?? "<udid>").map { "\(xcrunName) \($0.joined(separator: " "))" }.joined(separator: " && ")
    }
}

private extension SimulatorAccessibility {
    /// What one read of the deciding key found.
    ///
    /// Four outcomes rather than two, because the three ways a read can fail are three different things to say — see ``SimulatorAccessibility/Restoration/State``.
    enum Reading: Equatable {
        /// The value the device's own `defaults` printed.
        case value(String)
        /// `defaults` says the domain or the key is not there, so no session has ever switched the preference off on this device and there is nothing to restore.
        case never
        /// No spawn can reach the device: it is not booted, or `simctl` knows no device of that identifier.
        case unreachable(reason: String)
        /// The read failed some other way, a spawn that hit its deadline included.
        case unreadable(reason: String)
    }

    /// Reads until the teardown's `0` shows or ``teardownBudget`` has elapsed, answering what the last read found.
    ///
    /// **The budget is short because the wait is nearly over before it starts.** `swift-sure run` returns only once `xcodebuild` has exited, and the teardown's write lands within milliseconds of that, so the first read almost always settles it; what is left to wait for is a runner that outlives its `xcodebuild` by a moment. A clock rather than a count of reads, because each read is a `simctl spawn` whose cost varies — and this is paid by every simulator test run, including the ones that started no UI session at all.
    ///
    /// **A device nothing can reach ends the poll at once.** Polling exists to catch a teardown that has not landed yet; a device that is not booted, or that `simctl` does not know, will not answer the tenth read any better than the first, and making a failing run wait two seconds to be told so is two seconds spent on nothing. A *missing* domain keeps its poll, because a first-ever session on this device writes the domain into existence as it tears down.
    static func waitForTeardown(
        udid: String,
        run: (String, [String]) throws -> Subprocess.Output,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Reading {
        let deadline = now().addingTimeInterval(teardownBudget)
        while true {
            let reading = read(udid: udid, run: run)
            if reading == .value(offValue) {
                return reading
            }
            if case .unreachable = reading {
                return reading
            }
            guard now() < deadline else {
                return settled(reading)
            }
            pause(pollInterval)
        }
    }

    /// What the poll's last reading means once there is no time left to read again: anything that is neither the teardown's `0` nor a plain `1` is a key nobody read, whatever bytes came back.
    static func settled(_ reading: Reading) -> Reading {
        guard case let .value(value) = reading, value != onValue else {
            return reading
        }
        return .unreadable(reason: "\(domain) \(key) could not be read")
    }

    /// Writes both keys back on and confirms the write held, writing again for as long as ``confirmationBudget`` lasts if a late teardown undoes it.
    ///
    /// Retrying failed writes also writes again after a write that failed outright, for a device just booted; a restore after a run answers a failed write at once. `stopped` is asked before every pause and every further round, and once it answers true nothing more is written or waited for: a run being torn down has deleted the device this would wait on.
    static func write(
        udid: String,
        knownOff: Bool,
        retryingFailedWrites: Bool = false,
        run: (String, [String]) throws -> Subprocess.Output,
        pause: (TimeInterval) -> Void,
        now: () -> Date,
        stopped: () -> Bool = { false }
    ) -> Restoration {
        let deadline = now().addingTimeInterval(confirmationBudget)
        // What the deciding key last read before the next write: whatever the caller saw on the way in, and
        // off again whenever a confirmation read `0` — the two reads that make "left off" a known state
        // rather than a guess.
        var lastReadOff = knownOff
        var writes = 0
        var attempts = 0
        writing: while true {
            guard !stopped() else {
                return Restoration(udid: udid, state: .unconfirmed(reason: "stopped"))
            }
            attempts += 1
            for key in keys {
                let result = try? run(xcrunPath, enableArguments(udid: udid, key: key))
                guard let written = result, written.succeeded else {
                    // A device just booted can refuse an early spawn, so a failed write is tried again for as long as the budget lasts.
                    if retryingFailedWrites, now() < deadline {
                        guard !stopped() else {
                            return Restoration(udid: udid, state: .unconfirmed(reason: "stopped"))
                        }
                        pause(confirmationDelay)
                        continue writing
                    }
                    // Known off only when the key that failed is the deciding one and it last read off. A failure
                    // on a later key comes after the deciding key was written and never read back, so that is
                    // unknown — as is a deciding key nobody has seen off.
                    // A spawn that hit its deadline says so on standard error; one that threw never ran at all.
                    let cause = result.map { firstLine(of: $0.standardError) } ?? "could not be started"
                    let reason = "writing \(domain) \(key) did not succeed after \(attempts) \(attempts == 1 ? "round" : "rounds"): \(cause)"
                    let knownOff = key == Self.key && lastReadOff
                    return Restoration(udid: udid, state: knownOff ? .failed(reason: reason) : .unconfirmed(reason: reason))
                }
            }
            writes += 1
            guard !stopped() else {
                return Restoration(udid: udid, state: .unconfirmed(reason: "stopped"))
            }
            pause(confirmationDelay)
            guard case let .value(held) = read(udid: udid, run: run) else {
                return Restoration(udid: udid, state: .unconfirmed(reason: "\(domain) \(key) could not be read back"))
            }
            if held == onValue {
                return Restoration(udid: udid, state: .restored)
            }
            lastReadOff = held == offValue
            // Written, and off again a moment later: a teardown landed after the write. Write again, for as long
            // as the budget lasts — a teardown is one write per session, so this ends quickly or not at all.
            guard now() < deadline else {
                let plural = writes == 1 ? "" : "s"
                // Switched back off only when the last read said so; any other value is a key nobody could read.
                let reason = lastReadOff ? "\(domain) \(key) was switched back off after \(writes) write\(plural)" : "\(domain) \(key) read neither on nor off after \(writes) write\(plural)"
                return Restoration(udid: udid, state: lastReadOff ? .failed(reason: reason) : .unconfirmed(reason: reason))
            }
        }
    }

    /// The first non-blank line of a tool's standard error, or what an exit that printed nothing there was.
    static func firstLine(of standardError: String) -> String {
        let lines = standardError.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty } ?? "it exited with nothing on standard error"
    }

    /// The udid a named destination resolves to in `simctl`'s listing, or `nil` when the listing does not settle it.
    static func resolve(name: String, osVersion: String?, run: (String, [String]) throws -> Subprocess.Output) -> String? {
        guard let listing = try? run(xcrunPath, SimulatorDestination.listArguments), listing.succeeded else {
            return nil
        }
        return SimulatorDestination.device(named: name, osVersion: osVersion, inListing: Data(listing.standardOutput.utf8))
    }

    static func enableArguments(udid: String, key: String) -> [String] {
        ["simctl", "spawn", udid, runtimeDefaults, "write", domain, key, "-bool", "true"]
    }

    /// The deciding key's value as the device's own `defaults` reports it, or which way the read failed.
    static func read(udid: String, run: (String, [String]) throws -> Subprocess.Output) -> Reading {
        guard let result = try? run(xcrunPath, readArguments(udid: udid)) else {
            return .unreadable(reason: "\(domain) \(key) could not be read")
        }
        guard result.succeeded else {
            return failure(from: result.standardError)
        }
        return .value(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Which of the three ways a read failed this standard error describes.
    ///
    /// **The ordinary failing run is the one this exists for.** `com.apple.Accessibility` is written into existence by a session's own teardown, so a device no session has ever run on does not have the domain at all — which is every run that died before a session started: a scheme error, a compile error, a destination that never resolved. Reading that as "the preference could not be read" put a warning on the headline of the commonest failing run there is, about a device nothing had switched off.
    ///
    /// The wordings are matched as fragments because they are another tool's prose, probed on 17 Sep 2026 against `xcrun simctl spawn` and `defaults` on macOS 27: `Error: Domain 'com.apple.Accessibility' not found.`, `Error: Could not find key 'AccessibilityEnabled' in domain 'com.apple.Accessibility'.`, `Process spawn via launchd failed because device is not booted.` and `Invalid device: <udid>`. The older `does not exist` spelling of the first pair is matched too, since the deployment floor is older than the machine this was probed on. Anything else is the unknown it was before, and keeps the warning it earned.
    static func failure(from standardError: String) -> Reading {
        let text = standardError.lowercased()
        // The device before the domain: a device out of reach is why a read of *any* domain on it failed, and
        // reading that as a domain nobody has written would go quiet over a device this never looked at.
        for (shape, reason) in unreachableShapes where text.contains(shape) {
            return .unreachable(reason: reason)
        }
        if missingShapes.contains(where: text.contains) {
            return .never
        }
        let detail = standardError.split(separator: "\n").first.map { " (\($0.trimmingCharacters(in: .whitespaces)))" } ?? ""
        return .unreadable(reason: "\(domain) \(key) could not be read\(detail)")
    }

    /// The standard-error fragments that say the preference was never written on this device, spelled tightly enough that a `defaults` the runtime could not run at all is not mistaken for one.
    static var missingShapes: [String] {
        ["domain '\(domain.lowercased())' not found", "could not find key '\(key.lowercased())'", "does not exist"]
    }

    /// The standard-error fragments that say the device itself is out of reach, each with what a reader is told about it.
    static var unreachableShapes: [(String, String)] {
        [
            ("device is not booted", "the simulator is shut down"),
            ("unable to lookup in current state", "the simulator is shut down"),
            ("invalid device", "simctl knows no device with that identifier"),
        ]
    }

    /// The runtime's `defaults`, resolved inside the simulator's root because it is not an absolute path.
    static var runtimeDefaults: String {
        "defaults"
    }

    /// What the preference reads when on — the state an in-process accessibility suite needs.
    static var onValue: String {
        "1"
    }

    /// What it reads once the session teardown has switched it off.
    static var offValue: String {
        "0"
    }

    /// How long the restore gives the teardown to show before reporting the preference already on, in seconds of wall clock.
    static var teardownBudget: TimeInterval {
        2
    }

    static var pollInterval: TimeInterval {
        0.25
    }

    /// How long after a write the restore reads again to see that it held.
    static var confirmationDelay: TimeInterval {
        2.5
    }

    /// How long the restore keeps writing back a value a late teardown keeps undoing before it says so.
    static var confirmationBudget: TimeInterval {
        10
    }
}

/// How every `simctl` call in this module is spelled, since the other simulator work here spawns the same tool and quotes the same command back to a person.
extension SimulatorAccessibility {
    /// Writes both keys on and confirms the write held, for a caller outside this file that arms a device.
    ///
    /// `knownOff` is what the caller has seen: `true` only after a reading of exactly the off value. A write that fails on a device nobody saw off is unconfirmed rather than failed, since nothing says it was ever off.
    ///
    /// A failed write is tried again within the budget, since a device just booted can refuse an early spawn. `stopped` ends the writing and the waiting at once, for a run being torn down.
    static func armConfirmed(
        udid: String,
        knownOff: Bool,
        run: (String, [String]) throws -> Subprocess.Output,
        pause: (TimeInterval) -> Void,
        now: () -> Date,
        stopped: () -> Bool = { false }
    ) -> Restoration {
        write(udid: udid, knownOff: knownOff, retryingFailedWrites: true, run: run, pause: pause, now: now, stopped: stopped)
    }

    /// What the deciding key reads right now, as far as a caller deciding whether to arm it needs to know.
    enum Preference {
        case switchedOn
        case switchedOff
        /// Not readable, or neither `1` nor `0`.
        case unknown
    }

    /// The deciding key's reading, collapsed to on, off or unknown.
    static func preference(udid: String, run: (String, [String]) throws -> Subprocess.Output) -> Preference {
        switch read(udid: udid, run: run) {
        case .value(onValue):
            .switchedOn
        case .value(offValue):
            .switchedOff
        default:
            .unknown
        }
    }

    static var xcrunPath: String {
        "/usr/bin/\(xcrunName)"
    }

    static var xcrunName: String {
        "xcrun"
    }
}

public extension SimulatorAccessibility {
    /// What a restore did, and the one line an answer prints about it.
    struct Restoration: Equatable, Sendable {
        /// The device acted on, or `nil` where argv and the listing between them did not name one.
        public let udid: String?
        public let state: State

        public init(udid: String?, state: State) {
            self.udid = udid
            self.state = state
        }

        /// The one line the answer prints about this device, or `nil` where there is nothing to say.
        ///
        /// **Silent over a preference that read on, unless the failures read empty trees.** That is the reading of nearly every simulator run, green ones included, and a line printed on all of them is a line every reader learns to filter out — so the device that read on throughout the poll earns a line only where the run's failures have the shape a later teardown would explain. A preference read off is always said, in one short line, because the reader's next suite on that device depends on it; a device no session ever wrote says nothing, since nothing was switched off.
        ///
        /// **The re-arm command is printed once, and only where the reader may have a write to make**: never beside a restore that saw its own write hold, and in full everywhere else, because this tool has no shorter route to the same two writes. Whether the failures read empty trees is the reading ``RunDominantFailureClass/readsEmptyTree`` makes.
        public func note(failuresReadEmptyTrees: Bool) -> String? {
            let manual = SimulatorAccessibility.command(udid: udid)
            let device = udid ?? "<udid>"
            return switch state {
            case .restored:
                "accessibility: read off on \(device) after the run; \(ProductName.current.binary) switched it back on"
            case .alreadyOn:
                failuresReadEmptyTrees
                    ? "accessibility: read on for \(device) after the run, yet the failures read empty trees — if a late teardown switched it off, re-arm: \(manual)"
                    : nil
            case .neverSwitchedOff:
                nil
            case let .unreached(reason):
                "accessibility: not checked on \(device) (\(reason)) — if accessibility tests read empty trees, re-arm: \(manual)"
            case let .failed(reason):
                "accessibility: left off on \(device) (\(reason)) — re-arm: \(manual)"
            case let .unconfirmed(reason):
                "accessibility: not confirmed on for \(device) (\(reason)) — re-arm: \(manual)"
            case let .undetermined(reason):
                "accessibility: no device determined (\(reason)) — if accessibility tests read empty trees, re-arm: \(manual)"
            }
        }

        /// What this qualifies the run's verdict line by, or `nil` when nothing about the device is worth the headline.
        ///
        /// On the headline rather than only in the note, because the headline is what a reader takes in first and a device that cannot run the next suite is exactly the thing they have to act on. **Only where something may actually have been switched off**: a domain no session ever wrote, and a device that could not be reached at all, are not the run's verdict's business — the first because nothing was taken, the second because the run's own failure is the thing to read and a second warning beside it is noise.
        public var qualification: String? {
            switch state {
            case .restored, .alreadyOn, .neverSwitchedOff, .unreached:
                nil
            case .failed:
                "device accessibility left off"
            case .unconfirmed:
                "device accessibility not confirmed on"
            case .undetermined:
                "device accessibility not restored"
            }
        }

        /// How bad this is beside another device's restoration, for the one qualification a headline has room for.
        ///
        /// Ordered by how sure the reading is that a device will fail the next suite: a device known off first, then one this could not confirm, then one it could not even name, then the two that are nobody's problem. `unreached` sorts above the settled states and below every qualified one, so the run whose devices are all fit or all out of reach carries no qualification at all.
        var severity: Int {
            switch state {
            case .restored, .alreadyOn, .neverSwitchedOff:
                0
            case .unreached:
                1
            case .undetermined:
                2
            case .unconfirmed:
                3
            case .failed:
                4
            }
        }
    }
}

public extension SimulatorAccessibility.Restoration {
    /// The seven things a restore can have found.
    enum State: Equatable, Sendable {
        /// The preference was seen off, switched back on, and still read on a few seconds later.
        case restored
        /// It read on, and still read on at the end of the poll, so nothing was written.
        ///
        /// Nothing is said about it unless the run's failures read empty trees, and then only that: a teardown landing after the poll is a thing this did not see, so the device is not claimed fit.
        case alreadyOn
        /// The domain or the key is not on the device at all, so no session has ever switched the preference off there and nothing was owed.
        ///
        /// The run that died before its first session started is the common way here, and it prints nothing.
        case neverSwitchedOff
        /// The device could not be reached to be read — it is not booted, or `simctl` knows no such device; the payload says which.
        ///
        /// Nothing is claimed about the preference, and nothing qualifies the verdict: the run's own failure is the thing to read.
        case unreached(reason: String)
        /// Known off: the deciding key last read off and could not be switched back on — a write that kept being switched off, or a write of the deciding key that failed after it was read off; the payload says which.
        case failed(reason: String)
        /// Not known either way: the key could not be read, or a write failed where it had not been seen off; the payload says which.
        case unconfirmed(reason: String)
        /// The run executed tests on a simulator argv and the listing between them could not name, so no device was read or written.
        case undetermined(reason: String)
    }
}
