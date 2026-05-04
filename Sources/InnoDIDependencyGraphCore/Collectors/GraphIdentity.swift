enum GraphIdentity {
    static func makeContainerID(fileRelativePath: String, declarationPath: [String]) -> String {
        let path = declarationPath.joined(separator: ".")
        return "\(fileRelativePath)#\(path)"
    }
}
