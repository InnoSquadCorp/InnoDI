import SwiftSyntax

protocol DeclarationPathTracking: AnyObject {
    var declarationPath: [String] { get set }
}

extension DeclarationPathTracking {
    func pushDeclarationContext(named name: String) {
        declarationPath.append(name)
    }

    @discardableResult
    func popDeclarationContext() -> String? {
        declarationPath.popLast()
    }
}
