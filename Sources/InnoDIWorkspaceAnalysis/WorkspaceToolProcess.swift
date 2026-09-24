import Darwin
import Dispatch
import Foundation

/// Host-tool execution shared by workspace verification and graph rendering.
/// Output stays in bounded memory; no log files depend on the caller's umask.
package struct WorkspaceToolResult {
    package let exitCode: Int32
    package let timedOut: Bool
    package let stdout: String
    package let stderr: String
    package let outputTruncated: Bool
}

package func runWorkspaceTool(
    executable: String,
    arguments: [String],
    directory: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    timeout: TimeInterval = 300,
    captureLimit: Int = 16_384,
    mergeOutput: Bool = false
) throws -> WorkspaceToolResult {
    guard timeout.isFinite, timeout > 0, captureLimit > 0 else { throw POSIXError(.EINVAL) }
    func check(_ code: Int32) throws {
        if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    }
    var outputFDs: [Int32] = [-1, -1]
    var errorFDs: [Int32] = [-1, -1]
    defer {
        for fd in outputFDs + errorFDs where fd >= 0 { _ = Darwin.close(fd) }
    }
    guard pipe(&outputFDs) == 0, pipe(&errorFDs) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    // pipe() may reuse a caller's closed stdin/stdout/stderr. Those numbers
    // must not also be sources (or close actions) for the child's stdio map.
    // Move only our owned descriptors; leave the caller's stdio state intact.
    func moveAboveStandardDescriptors(_ descriptors: inout [Int32]) throws {
        for index in descriptors.indices where descriptors[index] <= STDERR_FILENO {
            let moved = fcntl(descriptors[index], F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
            guard moved >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            _ = Darwin.close(descriptors[index])
            descriptors[index] = moved
        }
    }
    try moveAboveStandardDescriptors(&outputFDs)
    try moveAboveStandardDescriptors(&errorFDs)
    for fd in outputFDs + errorFDs { guard fcntl(fd, F_SETFD, FD_CLOEXEC) != -1 else { throw POSIXError(.EIO) } }
    for fd in [outputFDs[0], errorFDs[0]] {
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw POSIXError(.EIO) }
    }
    var actions: posix_spawn_file_actions_t?
    try check(posix_spawn_file_actions_init(&actions))
    defer { posix_spawn_file_actions_destroy(&actions) }
    try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
    try check(posix_spawn_file_actions_adddup2(&actions, outputFDs[1], STDOUT_FILENO))
    try check(posix_spawn_file_actions_adddup2(&actions, mergeOutput ? outputFDs[1] : errorFDs[1], STDERR_FILENO))
    for fd in outputFDs + errorFDs { try check(posix_spawn_file_actions_addclose(&actions, fd)) }
    if let directory {
        if #available(macOS 26, *) {
            try check(posix_spawn_file_actions_addchdir(&actions, directory.path))
        } else {
            try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        }
    }
    var attributes: posix_spawnattr_t?
    try check(posix_spawnattr_init(&attributes))
    defer { posix_spawnattr_destroy(&attributes) }
    try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
    try check(posix_spawnattr_setpgroup(&attributes, 0))

    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    let envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { for pointer in argv + envp { free(pointer) } }
    var pid: pid_t = 0
    try argv.withUnsafeBufferPointer { argvPointer in
        try envp.withUnsafeBufferPointer { envPointer in
            try check(posix_spawn(&pid, executable, &actions, &attributes, argvPointer.baseAddress!, envPointer.baseAddress!))
        }
    }
    // Keep the leader unreaped until group cleanup finishes, reserving its PID
    // so a reused PID cannot turn cleanup into a signal to an unrelated group.
    var reaped = false
    defer {
        if !reaped {
            _ = kill(-pid, SIGKILL)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
    }
    _ = Darwin.close(outputFDs[1]); outputFDs[1] = -1
    _ = Darwin.close(errorFDs[1]); errorFDs[1] = -1

    var stdout = Data()
    var stderr = Data()
    var truncated = false
    func drain(_ fd: Int32, into tail: inout Data) throws {
        var bytes = [UInt8](repeating: 0, count: 8_192)
        // Bound each polling round even if a producer never stops writing.
        for _ in 0..<8 {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { return }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            tail.append(contentsOf: bytes.prefix(count))
            if tail.count > captureLimit {
                truncated = true
                tail.removeFirst(tail.count - captureLimit)
            }
        }
    }
    func elapsed(since start: UInt64) -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }
    let start = DispatchTime.now().uptimeNanoseconds
    var timedOut = false
    while true {
        try drain(outputFDs[0], into: &stdout)
        try drain(errorFDs[0], into: &stderr)
        var info = siginfo_t()
        let waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
        if waited == -1 && errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD) }
        if waited == 0 && info.si_pid == pid { break }
        if elapsed(since: start) >= timeout { timedOut = true; break }
        usleep(5_000)
    }
    // A completed tool must not leave background helpers retaining our pipes.
    // Deliberately daemonized descendants that leave this group are outside this
    // ownership boundary; do not enumerate or signal arbitrary system processes.
    _ = kill(-pid, SIGTERM)
    let cleanupStart = DispatchTime.now().uptimeNanoseconds
    repeat {
        try drain(outputFDs[0], into: &stdout)
        try drain(errorFDs[0], into: &stderr)
        usleep(5_000)
    } while elapsed(since: cleanupStart) < 0.2
    _ = kill(-pid, SIGKILL)
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {
        if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD) }
    }
    reaped = true
    try drain(outputFDs[0], into: &stdout)
    try drain(errorFDs[0], into: &stderr)
    let signal = status & 0x7f
    return WorkspaceToolResult(
        exitCode: signal == 0 ? (status >> 8) & 0xff : 128 + signal,
        timedOut: timedOut,
        stdout: String(decoding: stdout, as: UTF8.self),
        stderr: String(decoding: stderr, as: UTF8.self),
        outputTruncated: truncated
    )
}
