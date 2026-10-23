//
// Copyright © Agulhas Labs
//

/// An environment variable the tool reads; the raw value is the part after the product prefix.
public enum EnvironmentVariable: String, CaseIterable, Sendable {
    case home = "HOME"
    case serverLog = "SERVER_LOG"
    case usageLog = "USAGE_LOG"
    case adviceDir = "ADVICE_DIR"
    case runLog = "RUN_LOG"
    case runLedger = "RUN_LEDGER"
    case progress = "PROGRESS"
    case mcpResume = "MCP_RESUME"
    case noAdvice = "NO_ADVICE"
    case animations = "ANIMATIONS"
    case partMarker = "PART_MARKER"
    case testReplayLimit = "TEST_REPLAY_LIMIT"
    case testHookBudget = "TEST_HOOK_BUDGET"
    case testInplaceBudget = "TEST_INPLACE_BUDGET"
    case testGitLimit = "TEST_GIT_LIMIT"
    case testHoldPutBack = "TEST_HOLD_PUT_BACK"

    /// The full variable name for this build's product.
    public var name: String {
        ProductName.current.environmentVariable(rawValue)
    }

    /// What `environment` holds for this variable: the current name's value, else the first legacy name's that is set.
    ///
    /// `names` is every name tried, current first; a parameter so a test can stand in a rename.
    public func value(in environment: [String: String], names: [ProductName] = ProductName.recognised) -> String? {
        for product in names {
            if let value = environment[product.environmentVariable(rawValue)] {
                return value
            }
        }
        return nil
    }
}
