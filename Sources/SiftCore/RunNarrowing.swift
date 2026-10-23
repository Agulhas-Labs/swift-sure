//
// Copyright © Agulhas Labs
//

/// Whether a recorded test run ran everything its runner would run unasked, read from the run's argv.
///
/// A run is narrowed unless every argument it carries is on a closed list: for `swift test`, `--parallel`, `--enable-code-coverage`, `--num-workers N`, `-c`/`--configuration debug` and the location options ``ProofKey`` drops; for `xcodebuild test`, `-scheme`, `-project`, `-workspace`, `-destination`, `-derivedDataPath`, `-resultBundlePath`, `-quiet` and `-parallel-testing-enabled`, each with its value, and the two additions `swift-sure run` makes itself, `-collect-test-diagnostics never` and `-enableCodeCoverage YES`. Anything else narrows, and so does any other command, and a record with no argv: an open list would let a filter nobody listed read as the whole suite.
struct RunNarrowing {
    private init() {}

    /// The `swift test` options that take a value and leave what runs unchanged, beside the location options.
    private static let swiftTestValued: Set<String> = ["--num-workers"]

    /// The `xcodebuild` options that take a value and leave which tests run unchanged.
    private static let xcodebuildValued: Set<String> = ["-scheme", "-project", "-workspace", "-destination", "-derivedDataPath", "-resultBundlePath", "-parallel-testing-enabled"]

    /// The `xcodebuild` options `swift-sure run` adds itself, each with the one value it adds, which leave which tests run unchanged.
    private static let ownAdditions: [String: String] = ["-collect-test-diagnostics": "never", "-enableCodeCoverage": "YES"]

    /// Whether `arguments`, a run's argv as spelled, ran its runner's whole suite; `nil` (a record from before argv was kept) is narrowed.
    static func isUnnarrowed(_ arguments: [String]?) -> Bool {
        guard let arguments, let runner = arguments.first else { return false }
        return switch runner {
        case "swift": arguments.count >= 2 && arguments[1] == "test" && swiftTestOptionsAreClosed(Array(arguments.dropFirst(2)))
        case "xcodebuild": xcodebuildOptionsAreClosed(Array(arguments.dropFirst()))
        default: false
        }
    }

    /// The words of `arguments` before their first narrowing flag, then each narrowing flag once and `×N` where it appears N > 1 times; `nil` where no flag narrows the run.
    ///
    /// A narrowing flag is a dashed word that is not on the closed list; `--filter=Gizmo` and `-only-testing:Gizmo` count under `--filter` and `-only-testing`.
    static func summary(_ arguments: [String]) -> String? {
        let neutral = swiftTestValued.union(ProofKey.locationOptions).union(xcodebuildValued).union(ownAdditions.keys)
            .union(["--parallel", "-c", "--configuration", "--enable-code-coverage", "-quiet"])
        var counts: [(flag: String, count: Int)] = []
        var prefix: [String]?
        for (index, word) in arguments.enumerated() where word.hasPrefix("-") {
            let flag = String(word.prefix { $0 != "=" && $0 != ":" })
            guard !neutral.contains(flag) else { continue }
            prefix = prefix ?? Array(arguments[..<index])
            if let seen = counts.firstIndex(where: { $0.flag == flag }) {
                counts[seen].count += 1
            } else {
                counts.append((flag, 1))
            }
        }
        guard let prefix else { return nil }
        return (prefix + counts.map { $0.count > 1 ? "\($0.flag) ×\($0.count)" : $0.flag }).joined(separator: " ")
    }

    private static func swiftTestOptionsAreClosed(_ options: [String]) -> Bool {
        let valued = swiftTestValued.union(ProofKey.locationOptions)
        var index = 0
        while index < options.count {
            let option = options[index]
            if option == "--parallel" {
                index += 1
            } else if option == "-c" || option == "--configuration" {
                guard index + 1 < options.count, options[index + 1] == "debug" else { return false }
                index += 2
            } else if option == "--enable-code-coverage" {
                index += 1
            } else if option == "--configuration=debug" {
                index += 1
            } else if valued.contains(option) {
                guard index + 1 < options.count else { return false }
                index += 2
            } else if let equals = option.firstIndex(of: "="), valued.contains(String(option[..<equals])) {
                index += 1
            } else {
                return false
            }
        }
        return true
    }

    private static func xcodebuildOptionsAreClosed(_ options: [String]) -> Bool {
        var index = 0
        var actions = 0
        while index < options.count {
            let option = options[index]
            if option == "test" {
                actions += 1
                index += 1
            } else if option == "-quiet" {
                index += 1
            } else if let value = ownAdditions[option] {
                guard index + 1 < options.count, options[index + 1] == value else { return false }
                index += 2
            } else if xcodebuildValued.contains(option) {
                guard index + 1 < options.count else { return false }
                index += 2
            } else {
                return false
            }
        }
        return actions == 1
    }
}
