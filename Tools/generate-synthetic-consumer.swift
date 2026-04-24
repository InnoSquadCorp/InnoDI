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
        let outputURL = URL(fileURLWithPath: argv[1])
        let bindingCount = argv.count >= 3 ? (Int(argv[2]) ?? 100) : 100
        return Arguments(outputURL: outputURL, bindingCount: bindingCount)
    }
}

func write(_ content: String, to url: URL) throws {
    try content.data(using: .utf8)?.write(to: url)
}

let args = Arguments.parse()
let fileManager = FileManager.default
try? fileManager.removeItem(at: args.outputURL)
try fileManager.createDirectory(at: args.outputURL, withIntermediateDirectories: true)

let sourcesDir = args.outputURL.appendingPathComponent("Sources/Consumer", isDirectory: true)
try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

let packagePath = args.outputURL.appendingPathComponent("Package.swift")
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
            .package(name: "InnoDI", path: "../..")
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
        "    @Provide(.shared, factory: Double(input\(index)) * 1.5) var shared\(index): Double"
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

print("Generated synthetic consumer at \(args.outputURL.path) with \(args.bindingCount) bindings.")
