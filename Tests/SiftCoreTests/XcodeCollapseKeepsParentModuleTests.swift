//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Pins that collapsing never hands a directory's own files to the module of the directories beneath it.
struct XcodeCollapseKeepsParentModuleTests {
    private static let gizmoMap: [String: String] = [
        "Top/Mid/own.swift": "GizmoApp",
        "Top/Mid/Left/one.swift": "GizmoCore",
        "Top/Mid/Right/two.swift": "GizmoCore",
        "Top/Side/three.swift": "GizmoApp",
    ]

    @Test
    func aParentHoldingAnotherModuleIsNotLiftedOver() {
        #expect(XcodeProjectTargets.collapsed(Self.gizmoMap) == [
            "Top": "GizmoApp",
            "Top/Mid/Left": "GizmoCore",
            "Top/Mid/Right": "GizmoCore",
        ])
    }

    @Test
    func everyFileStillResolvesToItsOwnModule() {
        var shared: [String: String] = [:]
        for copy in 0 ..< 4 {
            shared["Top\(copy)/Mid/own.swift"] = "Module\(copy)"
            shared["Top\(copy)/Mid/Left/one.swift"] = "Module\(copy)"
            shared["Top\(copy)/Mid/Right/two.swift"] = "Module\(copy)"
            shared["Top\(copy)/Side/three.swift"] = "Module\(copy)"
        }
        for perFile in [Self.gizmoMap, shared] {
            let collapsed = XcodeProjectTargets.collapsed(perFile)
            for (path, module) in perFile {
                #expect(Self.module(of: path, in: collapsed) == module, "\(path)")
            }
        }
    }

    /// The resolver's rule: the longest prefix that is the path or a directory above it.
    private static func module(of path: String, in map: [String: String]) -> String? {
        map.keys
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
            .flatMap { map[$0] }
    }
}
