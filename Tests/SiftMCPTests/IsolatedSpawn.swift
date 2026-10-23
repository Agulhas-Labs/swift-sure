//
// Copyright © Agulhas Labs
//

import Foundation

/// Spawns a child of the test process that inherits nothing but standard input, output and error, all on the null device.
///
/// A spawn with no attributes copies every descriptor of the test process into the child, including the write end of any pipe another thread is reading a process's output from, and that reader then never sees end-of-file while the child lives.
struct IsolatedSpawn {
    /// Starts `path` with `arguments` and `environment`; the status of the spawn itself, and the child's pid when it is zero.
    static func start(_ path: String, arguments: [String], environment: [String: String] = [:]) -> (status: Int32, pid: pid_t) {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv + envp {
                free(pointer)
            }
        }
        var pid = pid_t()
        let status = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        return (status, pid)
    }
}
