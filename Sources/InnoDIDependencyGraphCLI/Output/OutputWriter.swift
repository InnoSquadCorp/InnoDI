import Foundation
import InnoDIWorkspaceAnalysis

func writeGraphOutput(_ content: String, format: OutputFormat, outputPath: String?) -> Int32 {
    guard let outputPath, outputPath != "-" else {
        print(content)
        return ExitCode.success
    }

    if outputPath.hasSuffix(".png") && format == .dot {
        return writeDOTAsPNG(dotContent: content, outputPath: outputPath)
    }

    do {
        try content.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        return ExitCode.success
    } catch {
        fputs("Error writing to file: \(error)\n", stderr)
        return ExitCode.ioError
    }
}

func writeDOTAsPNG(
    dotContent: String,
    outputPath: String,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    timeout: TimeInterval = 30
) -> Int32 {
    do {
        let tempDirectory = try makePrivateTemporaryDirectory(prefix: "innodi-dot")
        let tempURL = tempDirectory.appendingPathComponent("graph.dot")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        try dotContent.write(to: tempURL, atomically: true, encoding: .utf8)

        guard let dotPath = resolveDotExecutable(environment: environment), !dotPath.isEmpty else {
            fputs("dot command not found. Please install Graphviz.\n", stderr)
            return ExitCode.failure
        }

        let output = try runWorkspaceTool(
            executable: dotPath,
            arguments: ["-Tpng", tempURL.path(percentEncoded: false), "-o", outputPath],
            environment: environment,
            timeout: timeout
        )

        if !output.timedOut && output.exitCode == 0 {
            print("PNG generated at \(outputPath)")
            return ExitCode.success
        }

        fputs(
            """
            Failed to generate PNG with Graphviz 'dot' (exit \(output.exitCode), timeout=\(output.timedOut), truncated=\(output.outputTruncated)).
            stdout:
            \(output.stdout.isEmpty ? "<empty>" : output.stdout)
            stderr:
            \(output.stderr.isEmpty ? "<empty>" : output.stderr)

            """,
            stderr
        )
        return ExitCode.failure
    } catch {
        fputs("Error generating PNG: \(error)\n", stderr)
        return ExitCode.failure
    }
}

func resolveDotExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
    if let explicitPath = environment["INNODI_GRAPHVIZ_DOT"],
       isExecutableFile(atPath: explicitPath) {
        return explicitPath
    }

    let searchPaths = (environment["PATH"] ?? "")
        .split(separator: ":", omittingEmptySubsequences: true)
        .map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    for directory in searchPaths {
        let candidate = (directory as NSString).appendingPathComponent("dot")
        if isExecutableFile(atPath: candidate) {
            return candidate
        }
    }

    return nil
}

private func isExecutableFile(atPath path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
        && FileManager.default.isExecutableFile(atPath: path)
}

private func makePrivateTemporaryDirectory(prefix: String) throws -> URL {
    let fileManager = FileManager.default
    let url = fileManager.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return url
}
