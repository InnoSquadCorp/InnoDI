import InnoDICore
import SwiftSyntax

typealias ProvideScope = InnoDICore.ProvideScope
typealias ProvideArguments = InnoDICore.ProvideArguments
typealias DIContainerAttributeInfo = InnoDICore.DIContainerAttributeInfo

func parseProvideArguments(_ attribute: AttributeSyntax) -> ProvideArguments {
    InnoDICore.parseProvideArguments(attribute)
}

func parseDIContainerAttribute(_ attributes: AttributeListSyntax?) -> DIContainerAttributeInfo? {
    InnoDICore.parseDIContainerAttribute(attributes)
}
