import Foundation

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
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Int32 {
    do {
        let tempFileName = "innodi_temp_\(ProcessInfo.processInfo.globallyUniqueString).dot"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempFileName)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try dotContent.write(to: tempURL, atomically: true, encoding: .utf8)

        guard let dotPath = resolveDotExecutable(environment: environment), !dotPath.isEmpty else {
            fputs("dot command not found. Please install Graphviz.\n", stderr)
            return ExitCode.failure
        }

        let output = try runProcessCapturingOutput(
            executablePath: dotPath,
            arguments: ["-Tpng", tempURL.path(percentEncoded: false), "-o", outputPath]
        )

        if output.exitCode == 0 {
            print("PNG generated at \(outputPath)")
            return ExitCode.success
        }

        fputs(
            """
            Failed to generate PNG with Graphviz 'dot' (exit \(output.exitCode)).
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

private struct CapturedProcessOutput: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func runProcessCapturingOutput(
    executablePath: String,
    arguments: [String]
) throws -> CapturedProcessOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return CapturedProcessOutput(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

private func isExecutableFile(atPath path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
        && FileManager.default.isExecutableFile(atPath: path)
}
