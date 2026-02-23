protocol DeclarationPathTracking: AnyObject {
    var declarationPath: [String] { get set }
}

extension DeclarationPathTracking {
    func beginDeclarationContext(named name: String) {
        declarationPath.append(name)
    }

    @discardableResult
    func endDeclarationContext() -> String? {
        declarationPath.popLast()
    }
}
