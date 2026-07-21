import Foundation

func makeTemporaryWorkspaceRoot() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-WorkspaceHierarchy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
}

func writeSwiftPMManifest(_ contents: String, to rootURL: URL) throws {
    try contents.write(
        to: rootURL.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )
}

func writeSource(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
