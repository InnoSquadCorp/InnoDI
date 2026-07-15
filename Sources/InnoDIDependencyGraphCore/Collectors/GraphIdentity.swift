enum GraphIdentity {
    static func makeContainerID(
        fileRelativePath: String,
        declarationPath: [String],
        moduleIdentity: String? = nil
    ) -> String {
        let path = declarationPath.joined(separator: ".")
        if let moduleIdentity {
            return "\(moduleIdentity)::\(path)"
        }
        return "\(fileRelativePath)#\(path)"
    }
}
