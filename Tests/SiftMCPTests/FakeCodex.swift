//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// A `codex` that keeps servers by name in memory (`swift-sure` first) and answers `mcp get`, `add` and `remove` as the real one did when probed, recording every call.
final class FakeCodex: CodexMcpRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let present: Bool
    private let getError: String?
    private var recorded: [Call] = []
    private var servers: [String: (command: String, arguments: [String])] = [:]

    /// A `codex` on PATH (`present`) holding `server` as `swift-sure` and each of `others` under its own name, whose `get` fails with `getError` when one is given.
    init(present: Bool = true, server: (command: String, arguments: [String])? = nil, others: [String: (command: String, arguments: [String])] = [:], getError: String? = nil) {
        self.present = present
        servers = others
        servers["swift-sure"] = server
        self.getError = getError
    }

    /// Every run, in order.
    var calls: [Call] {
        lock.withLock { recorded }
    }

    /// The server named `swift-sure`, as the last run left it.
    var server: (command: String, arguments: [String])? {
        lock.withLock { servers["swift-sure"] }
    }

    /// The server named `name`, as the last run left it.
    func server(named name: String) -> (command: String, arguments: [String])? {
        lock.withLock { servers[name] }
    }

    func run(_ arguments: [String], home: URL) throws -> Subprocess.Output? {
        guard present else { return nil }
        return lock.withLock {
            recorded.append(Call(arguments: arguments, home: home.path))
            let name = arguments.count > 2 ? arguments[2] : ""
            switch Array(arguments.prefix(2)) {
            case ["mcp", "get"]:
                if let getError {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: getError)
                }
                guard let registered = servers[name] else {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "Error: No MCP server named '\(name)' found.")
                }
                let shown: [String: Any] = ["name": name, "transport": ["type": "stdio", "command": registered.command, "args": registered.arguments]]
                let json = (try? JSONSerialization.data(withJSONObject: shown)).map { String(bytes: $0, encoding: .utf8) ?? "" } ?? ""
                return Subprocess.Output(succeeded: true, standardOutput: json)
            case ["mcp", "add"]:
                let command = arguments.drop { $0 != "--" }.dropFirst()
                servers[name] = (command.first ?? "", Array(command.dropFirst()))
                return Subprocess.Output(succeeded: true, standardOutput: "Added global MCP server '\(name)'.")
            case ["mcp", "remove"]:
                servers[name] = nil
                return Subprocess.Output(succeeded: true, standardOutput: "Removed global MCP server '\(name)'.")
            default:
                return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "unexpected")
            }
        }
    }
}

extension FakeCodex {
    /// One run: the arguments exactly as passed and the Codex home it was pointed at.
    struct Call: Equatable {
        let arguments: [String]
        let home: String
    }
}
