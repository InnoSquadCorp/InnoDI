import Foundation

func writeGraphOutput(_ content: String, format: OutputFormat, outputPath: String?) -> Int32 {
    guard let outputPath else {
        print(content)
        return 0
    }

    if outputPath.hasSuffix(".png") && format == .dot {
        return writeDOTAsPNG(dotContent: content, outputPath: outputPath)
    }

    do {
        try content.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        return 0
    } catch {
        fputs("Error writing to file: \(error)\n", stderr)
        return 1
    }
}

private func writeDOTAsPNG(dotContent: String, outputPath: String) -> Int32 {
    do {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("innodi_temp.dot")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try dotContent.write(to: tempURL, atomically: true, encoding: .utf8)

        guard let dotPath = try resolveDotExecutable(), !dotPath.isEmpty else {
            fputs("dot command not found. Please install Graphviz.\n", stderr)
            return 1
        }

        let dotProcess = Process()
        dotProcess.executableURL = URL(fileURLWithPath: dotPath)
        dotProcess.arguments = ["-Tpng", tempURL.path(percentEncoded: false), "-o", outputPath]
        try dotProcess.run()
        dotProcess.waitUntilExit()

        if dotProcess.terminationStatus == 0 {
            print("PNG generated at \(outputPath)")
            return 0
        }

        fputs("Failed to generate PNG\n", stderr)
        return 1
    } catch {
        fputs("Error generating PNG: \(error)\n", stderr)
        return 1
    }
}

private func resolveDotExecutable() throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["dot"]

    let pipe = Pipe()
    process.standardOutput = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
