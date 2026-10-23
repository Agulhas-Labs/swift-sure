//
// Copyright © Agulhas Labs
//

import Foundation

/// The sanitizers a `.xctestplan` switches on, in its default options or any configuration's.
struct TestPlanSanitizers {
    /// The sanitizers the document switches on, by their option keys — every key ending `Sanitizer` whose `enabled` is true, or ending `SanitizerEnabled` and true, so one Xcode adds is refused too — or none where it does not decode.
    static func enabled(in data: Data) -> [String] {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let configurations = (document["configurations"] as? [[String: Any]] ?? []).compactMap { $0["options"] as? [String: Any] }
        let options = [document["defaultOptions"] as? [String: Any] ?? [:]] + configurations
        let switchedOn = options.flatMap { option in
            option.filter { key, value in isOn(key: key, value: value) }.keys
        }
        return Set(switchedOn).sorted()
    }

    /// Whether an option switches a sanitizer on: Xcode stores the address sanitizer as `{ "enabled": true }` under a key ending `Sanitizer`, and the thread and undefined-behavior sanitizers as a plain boolean under a key ending `SanitizerEnabled`.
    private static func isOn(key: String, value: Any) -> Bool {
        if key.hasSuffix("Sanitizer") {
            return ((value as? [String: Any])?["enabled"] as? Bool) == true
        }
        return key.hasSuffix("SanitizerEnabled") && (value as? Bool) == true
    }

    /// The first of `plans` whose file under `root` switches on a sanitizer, with the sanitizers, or `nil` where none does or the files cannot be found.
    static func first(among plans: [String], under root: URL) -> (plan: String, sanitizers: [String])? {
        guard !plans.isEmpty, let survey = try? TestPlanDiscovery.plans(under: root) else {
            return nil
        }
        for plan in plans {
            let sanitizers = survey.plans.filter { $0.name == plan }.flatMap { file in
                FileManager.default.contents(atPath: root.appendingPathComponent(file.path).path).map(enabled(in:)) ?? []
            }
            if !sanitizers.isEmpty {
                return (plan, sanitizers)
            }
        }
        return nil
    }
}
