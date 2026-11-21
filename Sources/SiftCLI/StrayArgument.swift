//
// Copyright © Agulhas Labs
//

import Foundation

/// The refusal for a stray argument on a command that collects its unrecognised words, worded as ArgumentParser words them: an unknown option is not an unexpected argument.
struct StrayArgument {
    /// The message for `stray`, with a suggestion from the long options `help` lists when it is an option written close to one of them.
    ///
    /// `help` is the command's `helpMessage()`, whose option lines name the long options (hidden ones are not listed).
    static func message(_ stray: String, help: String) -> String {
        guard stray.hasPrefix("-"), stray != "-" else {
            return "Unexpected argument '\(stray)'"
        }
        let known = longOptions(in: help)
        let spelled = stray.split(separator: "=", maxSplits: 1).first.map(String.init) ?? stray
        let closest = known.map { (name: $0, distance: editDistance(spelled, $0)) }.filter { $0.distance <= 2 }.min { $0.distance < $1.distance }
        guard let closest else {
            return "Unknown option '\(stray)'"
        }
        return "Unknown option '\(stray)'. Did you mean '\(closest.name)'?"
    }

    /// The `--name` an option line of `help` starts with, in the order listed.
    private static func longOptions(in help: String) -> [String] {
        var names: [String] = []
        for line in help.split(separator: "\n") where line.prefix(while: { $0 == " " }).count <= 4 {
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }
            guard let name = words.prefix(2).first(where: { $0.hasPrefix("--") && $0.count > 2 }), !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0 ... right.count)
        for (row, leftCharacter) in left.enumerated() {
            var current = [row + 1]
            for (column, rightCharacter) in right.enumerated() {
                current.append(min(previous[column + 1] + 1, current[column] + 1, previous[column] + (leftCharacter == rightCharacter ? 0 : 1)))
            }
            previous = current
        }
        return previous[right.count]
    }
}
