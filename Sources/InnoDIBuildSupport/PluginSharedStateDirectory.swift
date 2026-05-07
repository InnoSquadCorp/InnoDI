import Foundation

package func sharedValidationStateDirectory(forPluginOutputDirectory outputDirectory: URL) -> URL {
    let components = outputDirectory.pathComponents

    // sharedValidationStateDirectory(forPluginOutputDirectory:) depends on SwiftPM's
    // plugin work-directory shape: .../plugins/outputs/<package>/<target>/<plugin>.
    // It extracts through outputs/<package> so every target/plugin in one package
    // reuses state; revisit this if SwiftPM changes the plugin output layout.
    if let outputsIndex = components.indices.reversed().first(where: { index in
        components[index] == "outputs"
            && index > 0
            && components[index - 1] == "plugins"
            && index + 1 < components.count
    }) {
        return URL(
            fileURLWithPath: NSString.path(
                withComponents: Array(components.prefix(outputsIndex + 2))
            ),
            isDirectory: true
        )
        .appending(path: "innodi-dag-validation-state", directoryHint: .isDirectory)
    }

    var fallback = outputDirectory
    for _ in 0..<2 {
        let parent = fallback.deletingLastPathComponent()
        guard parent.path != fallback.path else { break }
        fallback = parent
    }
    return fallback.appending(path: "innodi-dag-validation-state", directoryHint: .isDirectory)
}
