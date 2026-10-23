//
// Copyright © Agulhas Labs
//

import Foundation

/// A signal's name, as an answer states it.
struct SignalName {
    /// The name of signal `number` where it has a common one, as in `SIGTERM`, else `signal N`.
    ///
    /// A number is something a reader has to go and look up, and the name is the answer.
    static func of(_ number: Int32) -> String {
        names[number] ?? "signal \(number)"
    }

    private static let names: [Int32: String] = [
        SIGHUP: "SIGHUP", SIGINT: "SIGINT", SIGQUIT: "SIGQUIT", SIGILL: "SIGILL", SIGTRAP: "SIGTRAP",
        SIGABRT: "SIGABRT", SIGFPE: "SIGFPE", SIGKILL: "SIGKILL", SIGBUS: "SIGBUS", SIGSEGV: "SIGSEGV",
        SIGPIPE: "SIGPIPE", SIGALRM: "SIGALRM", SIGTERM: "SIGTERM", SIGXCPU: "SIGXCPU", SIGUSR1: "SIGUSR1",
        SIGUSR2: "SIGUSR2",
    ]
}
