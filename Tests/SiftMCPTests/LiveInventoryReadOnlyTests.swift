//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// A run reads the repository's index for its declared tests and must leave a store it cannot read as it found it.
@Suite(.temporaryDirectories)
struct LiveInventoryReadOnlyTests {
    private static var source: String {
        """
        import Testing

        @Suite struct DepotTests {
            @Test func testOne() {
                #expect(true)
            }
        }
        """
    }

    @Test
    func aCurrentStoreStillYieldsItsInventory() async throws {
        let root = try await FlakesSuiteMatchTests.indexedRepository(files: ["Tests/GizmoTests/DepotTests.swift": Self.source])

        #expect(TestRunEnvironment.liveInventory(repositoryRoot: root) != nil)
    }

    @Test
    func aStoreAtAnotherSchemaVersionIsLeftUntouched() async throws {
        let root = try await FlakesSuiteMatchTests.indexedRepository(files: ["Tests/GizmoTests/DepotTests.swift": Self.source])
        _ = try FlakesSuiteMatchTests.sqlite("PRAGMA user_version=9999;", in: root)
        let tables = try FlakesSuiteMatchTests.sqlite("SELECT count(*) FROM sqlite_master WHERE type='table';", in: root)

        #expect(TestRunEnvironment.liveInventory(repositoryRoot: root) == nil)
        #expect(try FlakesSuiteMatchTests.sqlite("PRAGMA user_version;", in: root) == "9999")
        #expect(try FlakesSuiteMatchTests.sqlite("SELECT count(*) FROM sqlite_master WHERE type='table';", in: root) == tables)
    }
}
