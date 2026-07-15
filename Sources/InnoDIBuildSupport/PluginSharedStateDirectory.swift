import Foundation
import InnoDIWorkspaceAnalysis

package func sharedValidationStateDirectory(forPluginOutputDirectory outputDirectory: URL) -> URL {
    // A build-tool plugin may only write inside its own plugin work directory.
    // Do not infer a package-level ancestor from SwiftPM's private output shape:
    // that directory is outside the invoking plugin's sandbox on some SwiftPM
    // versions and causes NSCocoaErrorDomain 513 / POSIX EPERM failures.
    outputDirectory.appending(
        path: "innodi-dag-validation-state",
        directoryHint: .isDirectory
    )
}

/// Isolates AST digests, locks, and shared-run results for one stable target.
///
/// The plugin-invocation base stays inside SwiftPM's writable sandbox, while
/// the target hash prevents a reused work directory from accepting a result
/// computed for a different source closure.
package func targetScopedValidationStateDirectory(
    for targetID: WorkspaceTargetID,
    under sharedStateDirectory: URL
) -> URL {
    var hasher = StableHasher()
    hasher.combine("target-state-v1:\(targetID.rawValue)")
    return sharedStateDirectory
        .appending(path: "targets", directoryHint: .isDirectory)
        .appending(path: hasher.finalize(), directoryHint: .isDirectory)
}
