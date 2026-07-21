import Dispatch
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct CapturedProcessTree {
    let rootProcessID: Int32
    private var descendants: [CapturedProcessIdentity]

    init(rootProcessID: Int32) {
        self.rootProcessID = rootProcessID
        descendants = Self.captureDescendants(of: rootProcessID)
    }

    mutating func refresh() {
        var seen = Set(descendants)
        for identity in Self.captureDescendants(of: rootProcessID)
        where seen.insert(identity).inserted {
            descendants.append(identity)
        }
    }

    func sendToDescendants(_ signal: Int32) {
        guard let table = processTableSnapshot() else { return }
        for identity in descendants
        where table[identity.processID]?.identity == identity {
            _ = kill(identity.processID, signal)
        }
    }

    var hasRunningDescendants: Bool {
        guard !descendants.isEmpty,
              let table = processTableSnapshot() else {
            return false
        }
        return descendants.contains { identity in
            table[identity.processID]?.identity == identity
        }
    }

    func waitForDescendantsToExit(deadline: DispatchTime) -> Bool {
        guard !descendants.isEmpty else { return true }
        while DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds {
            if !hasRunningDescendants {
                return true
            }
            let remainingNanoseconds = deadline.uptimeNanoseconds
                - DispatchTime.now().uptimeNanoseconds
            let sleepMicroseconds = useconds_t(
                min(remainingNanoseconds / 1_000, 50_000)
            )
            if sleepMicroseconds > 0 {
                usleep(sleepMicroseconds)
            }
        }
        return !hasRunningDescendants
    }

    private static func captureDescendants(
        of rootPID: Int32
    ) -> [CapturedProcessIdentity] {
        guard let table = processTableSnapshot() else { return [] }
        var childrenByParent: [Int32: [ProcessTableEntry]] = [:]
        for entry in table.values {
            childrenByParent[entry.parentProcessID, default: []].append(entry)
        }

        var pending: [(processID: Int32, depth: Int)] = [(rootPID, 0)]
        var result: [(identity: CapturedProcessIdentity, depth: Int)] = []
        while let current = pending.popLast() {
            for child in childrenByParent[current.processID] ?? [] {
                let depth = current.depth + 1
                result.append((child.identity, depth))
                pending.append((child.identity.processID, depth))
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.depth != rhs.depth { return lhs.depth > rhs.depth }
            return lhs.identity.processID > rhs.identity.processID
        }.map(\.identity)
    }
}

func capturedProcessDeadline(after seconds: TimeInterval) -> DispatchTime {
    .now() + max(0, seconds)
}

private struct CapturedProcessIdentity: Hashable {
    let processID: Int32
    let startFingerprint: String
}

private struct ProcessTableEntry {
    let identity: CapturedProcessIdentity
    let parentProcessID: Int32
}

private func processTableSnapshot() -> [Int32: ProcessTableEntry]? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
#if canImport(Darwin)
    process.arguments = ["-axo", "pid=,ppid=,lstart="]
#else
    process.arguments = ["-eo", "pid=,ppid=,lstart="]
#endif
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseProcessTable(output)
    } catch {
        return nil
    }
}

private func parseProcessTable(
    _ data: Data
) -> [Int32: ProcessTableEntry] {
    let output = String(decoding: data, as: UTF8.self)
    return output.split(whereSeparator: \.isNewline).reduce(into: [:]) { table, line in
        let fields = line.split(
            maxSplits: 2,
            omittingEmptySubsequences: true,
            whereSeparator: \.isWhitespace
        )
        guard fields.count == 3,
              let processID = Int32(fields[0]),
              let parentProcessID = Int32(fields[1]) else {
            return
        }
        let identity = CapturedProcessIdentity(
            processID: processID,
            startFingerprint: String(fields[2])
        )
        table[processID] = ProcessTableEntry(
            identity: identity,
            parentProcessID: parentProcessID
        )
    }
}
