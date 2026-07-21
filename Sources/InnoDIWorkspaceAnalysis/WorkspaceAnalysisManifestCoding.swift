import Foundation

package func loadWorkspaceAnalysisManifest(
    at url: URL,
    validateSourceAvailability: Bool = true,
    fileManager: FileManager = .default
) throws -> WorkspaceAnalysisManifest {
    do {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(
            WorkspaceAnalysisManifest.self,
            from: data
        )
        return try manifest.validated(
            validateSourceAvailability: validateSourceAvailability,
            fileManager: fileManager
        )
    } catch let error as WorkspaceAnalysisManifestError {
        throw error
    } catch {
        throw WorkspaceAnalysisManifestError.decodingFailed(
            String(describing: error)
        )
    }
}

package func encodeWorkspaceAnalysisManifest(
    _ manifest: WorkspaceAnalysisManifest,
    validateSourceAvailability: Bool = true,
    fileManager: FileManager = .default
) throws -> Data {
    let normalized = try manifest.validated(
        validateSourceAvailability: validateSourceAvailability,
        fileManager: fileManager
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(normalized)
}
