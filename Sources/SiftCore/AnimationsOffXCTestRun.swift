//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorAnimations

/// The run's copy of an `.xctestrun`, with the animations-off library inserted into the app of every UI test target.
struct AnimationsOffXCTestRun {
    private static var placeholder: String {
        "__TESTROOT__"
    }

    private static var appEnvironmentKey: String {
        "UITargetAppEnvironmentVariables"
    }

    private static var insertKey: String {
        "DYLD_INSERT_LIBRARIES"
    }

    /// The property list `data` holds, written for a copy that lives away from the original's directory, with `library` inserted into every UI test target's app.
    ///
    /// Every `__TESTROOT__` becomes that directory's path, so the copy still finds the products beside the original; the other placeholders resolve on their own and are left alone. A library already named by `DYLD_INSERT_LIBRARIES` is kept, with this one appended after a colon. Both the flat layout (each target beside the metadata) and the test-plan layout (`TestConfigurations`, each with `TestTargets`) are read. `nil` when no target is a UI test bundle, so the original runs unchanged.
    static func rewritten(_ data: Data, originalDirectory: URL, library: URL) throws -> Data? {
        guard var root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw AnimationsOffError.notADictionary
        }
        root = replacingPlaceholder(in: root, with: originalDirectory.path) as? [String: Any] ?? root
        var foundUITarget = false

        func insert(into target: inout [String: Any]) {
            guard target["IsUITestBundle"] as? Bool == true else { return }
            foundUITarget = true
            var environment = target[appEnvironmentKey] as? [String: Any] ?? [:]
            environment[insertKey] = AnimationsOffLibrary.insertingLibrary(library, into: environment[insertKey] as? String)
            target[appEnvironmentKey] = environment
        }

        if var configurations = root["TestConfigurations"] as? [[String: Any]] {
            for index in configurations.indices {
                guard var targets = configurations[index]["TestTargets"] as? [[String: Any]] else { continue }
                for position in targets.indices {
                    insert(into: &targets[position])
                }
                configurations[index]["TestTargets"] = targets
            }
            root["TestConfigurations"] = configurations
        } else {
            for (key, value) in root {
                guard var target = value as? [String: Any] else { continue }
                insert(into: &target)
                root[key] = target
            }
        }
        guard foundUITarget else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    /// `value` with `__TESTROOT__` replaced by `path` in every string, however deep in dictionaries and arrays.
    private static func replacingPlaceholder(in value: Any, with path: String) -> Any {
        switch value {
        case let text as String:
            text.replacingOccurrences(of: placeholder, with: path)
        case let dictionary as [String: Any]:
            dictionary.mapValues { replacingPlaceholder(in: $0, with: path) }
        case let array as [Any]:
            array.map { replacingPlaceholder(in: $0, with: path) }
        default:
            value
        }
    }
}
