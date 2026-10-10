import Foundation

package func xcodePluginOutputDirectory(
    basePath: String,
    environment: [String: String]
) throws -> URL {
    func component(_ name: String, allowsEmpty: Bool = false) throws -> String {
        let value = environment[name] ?? ""
        guard (allowsEmpty || !value.isEmpty), value != ".", value != "..",
              !value.contains("/"), !value.contains("\0") else {
            throw ValidationCoordinatorArgumentError.invalidXcodeBuildSetting(name)
        }
        return value
    }
    let configuration = try component("CONFIGURATION")
    let effectivePlatform = try component("EFFECTIVE_PLATFORM_NAME", allowsEmpty: true)
    let platform = try component("PLATFORM_NAME")
    return URL(fileURLWithPath: basePath, isDirectory: true)
        .appending(path: "xcode", directoryHint: .isDirectory)
        .appending(path: configuration + effectivePlatform, directoryHint: .isDirectory)
        .appending(path: platform, directoryHint: .isDirectory)
}
