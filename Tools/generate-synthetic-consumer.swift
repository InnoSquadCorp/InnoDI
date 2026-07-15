#!/usr/bin/env swift
//
//  generate-synthetic-consumer.swift
//  InnoDI
//
//  Generates a throw-away consumer package with N @DIContainer / @Provide
//  bindings so we can benchmark how long macro expansion + plugin
//  validation takes on realistic code sizes.
//
//  Invoke from the repo root:
//      swift Tools/generate-synthetic-consumer.swift <output-path> [binding-count]
//
//  The script only ever writes inside <output-path>; it never touches the
//  host repository files.

import Foundation

enum SyntheticConsumerGenerationError: LocalizedError {
    case unsafeOutputPath(String)

    var errorDescription: String? {
        switch self {
        case .unsafeOutputPath(let path):
            return "Refusing to delete unsafe output path: \(path)"
        }
    }
}

struct Arguments {
    let outputURL: URL
    let bindingCount: Int

    static func parse() -> Arguments {
        let argv = CommandLine.arguments
        guard argv.count >= 2 else {
            FileHandle.standardError.write(Data(
                "Usage: generate-synthetic-consumer.swift <output-path> [binding-count]\n".utf8
            ))
            exit(2)
        }
        let outputURL = URL(fileURLWithPath: argv[1]).standardizedFileURL
        let bindingCount = argv.count >= 3 ? (Int(argv[2]) ?? 100) : 100
        return Arguments(outputURL: outputURL, bindingCount: bindingCount)
    }
}

func write(_ content: String, to url: URL) throws {
    try content.write(to: url, atomically: true, encoding: .utf8)
}

func relativePath(from baseURL: URL, to targetURL: URL) -> String {
    let baseComponents = baseURL.standardizedFileURL.pathComponents
    let targetComponents = targetURL.standardizedFileURL.pathComponents
    let sharedCount = zip(baseComponents, targetComponents).prefix { pair in pair.0 == pair.1 }.count
    let up = Array(repeating: "..", count: baseComponents.count - sharedCount)
    let down = Array(targetComponents.dropFirst(sharedCount))
    let components = up + down
    return components.isEmpty ? "." : components.joined(separator: "/")
}

func outputPathIsInsideSyntheticDirectory(_ outputURL: URL, repoRootURL: URL) -> Bool {
    let syntheticPath = repoRootURL
        .appendingPathComponent("Tools/.synthetic", isDirectory: true)
        .standardizedFileURL
        .path
    let outputPath = outputURL.standardizedFileURL.path
    return outputPath == syntheticPath || outputPath.hasPrefix("\(syntheticPath)/")
}

func outputPathLooksLikeSyntheticConsumer(_ outputURL: URL) -> Bool {
    let packageURL = outputURL.appendingPathComponent("Package.swift")
    let mainURL = outputURL.appendingPathComponent("Sources/Consumer/main.swift")
    guard
        FileManager.default.fileExists(atPath: packageURL.path),
        FileManager.default.fileExists(atPath: mainURL.path),
        let packageContents = try? String(contentsOf: packageURL, encoding: .utf8)
    else {
        return false
    }
    return packageContents.contains("name: \"SyntheticConsumer\"")
}

let args = Arguments.parse()
let fileManager = FileManager.default
let repoRootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .standardizedFileURL
let outputURL = args.outputURL.standardizedFileURL

if fileManager.fileExists(atPath: outputURL.path) {
    guard outputPathIsInsideSyntheticDirectory(outputURL, repoRootURL: repoRootURL)
        || outputPathLooksLikeSyntheticConsumer(outputURL)
    else {
        throw SyntheticConsumerGenerationError.unsafeOutputPath(outputURL.path)
    }
    try fileManager.removeItem(at: outputURL)
}

try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sourcesDir = outputURL.appendingPathComponent("Sources/Consumer", isDirectory: true)
try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

let packagePath = outputURL.appendingPathComponent("Package.swift")
let innoDIPath = relativePath(from: outputURL, to: repoRootURL)
try write(
    """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "SyntheticConsumer",
        platforms: [
            .iOS(.v17),
            .macOS(.v13)
        ],
        dependencies: [
            .package(name: "InnoDI", path: "\(innoDIPath)")
        ],
        targets: [
            .executableTarget(
                name: "Consumer",
                dependencies: [
                    .product(name: "InnoDI", package: "InnoDI")
                ]
            )
        ]
    )
    """,
    to: packagePath
)

var inputLines: [String] = []
var sharedLines: [String] = []
var mainLines: [String] = ["let container = SyntheticContainer("]

for index in 0..<args.bindingCount {
    inputLines.append("    @Provide(.input) var input\(index): Int")
    sharedLines.append(
        "    @Provide(.shared, factory: { (input\(index): Int) in Double(input\(index)) * 1.5 }) var shared\(index): Double"
    )
    mainLines.append("    input\(index): \(index)\(index == args.bindingCount - 1 ? "" : ",")")
}
mainLines.append(")")
mainLines.append("print(\"Synthetic consumer built with \\(\(args.bindingCount)) inputs\")")

let sourceFile = sourcesDir.appendingPathComponent("main.swift")
try write(
    """
    import InnoDI

    @DIContainer
    struct SyntheticContainer {
    \(inputLines.joined(separator: "\n"))
    \(sharedLines.joined(separator: "\n"))
    }

    \(mainLines.joined(separator: "\n"))
    """,
    to: sourceFile
)

print("Generated synthetic consumer at \(outputURL.path) with \(args.bindingCount) bindings.")
