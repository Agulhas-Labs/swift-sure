//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a SwiftPM package scheme's build wrote its products, which `-showBuildSettings` does not say.
///
/// **A package scheme's settings list is empty.** For a scheme that lives in a package rather than a project or workspace, `xcodebuild -showBuildSettings -json` prints `[]` whatever the destination, so there is no `BUILD_DIR` to read. The build itself still wrote into a DerivedData folder, and that folder records the directory it was made for: its `info.plist` holds a `WorkspacePath` string, which is the package directory. The folder is found by that path and never by its name, since one package built from several checkouts leaves several folders of the same name.
public struct PackageProductsDirectory {
    /// The products directory for a build whose settings came back empty.
    ///
    /// A `-derivedDataPath` in the pass-through wins without any search, resolved against `workingDirectory` when relative. Otherwise `derivedDataRoot` is searched for the folders whose `WorkspacePath` is `workingDirectory`, and exactly one is required.
    static func resolve(workingDirectory: URL, passThrough: [String], derivedDataRoot: URL) throws -> String {
        if let flag = passThrough.lastIndex(of: "-derivedDataPath"), flag + 1 < passThrough.count {
            return TestInvocation.absoluteURL(passThrough[flag + 1], relativeTo: workingDirectory)
                .appendingPathComponent("Build/Products").path
        }
        let package = canonical(workingDirectory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: derivedDataRoot.path)) ?? []).sorted()
        let matches = names.filter { name in
            let plist = derivedDataRoot.appendingPathComponent(name).appendingPathComponent("info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let document = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let workspace = document["WorkspacePath"] as? String
            else {
                return false
            }
            return canonical(URL(fileURLWithPath: workspace)) == package
        }
        guard matches.count == 1, let match = matches.first else {
            throw TestInvocationError.noPackageProducts(packageDirectory: package, derivedDataRoot: derivedDataRoot.path, found: matches)
        }
        return derivedDataRoot.appendingPathComponent(match).appendingPathComponent("Build/Products").path
    }

    /// Whether `data` is a JSON array with no entry in it, which is what a package scheme's settings read prints.
    static func isEmptySettings(_ data: Data) -> Bool {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return false
        }
        return document.isEmpty
    }

    /// The DerivedData root Xcode itself uses: the custom location from its defaults where one is set, else the one under the home directory.
    public static func liveDerivedDataRoot() -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.dt.Xcode")?.string(forKey: "IDECustomDerivedDataLocation"), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
