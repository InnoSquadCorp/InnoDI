//
//  Parsing.swift
//  InnoDICore
//

import SwiftSyntax

/// Scope for a `@Provide` declaration.
public enum ProvideScope: String {
    /// Shared singleton-like instance in a container.
    case shared
    /// Input value passed from outside the container.
    case input
    /// New instance created on each access.
    case transient
}

/// Parsed arguments extracted from a single `@Provide` attribute.
public struct ProvideArguments {
    /// Parsed scope value (`.shared`, `.input`, `.transient`) when available.
    public let scope: ProvideScope?
    /// Raw textual scope name.
    public let scopeName: String?
    /// Factory expression passed via `factory:`.
    public let factoryExpr: ExprSyntax?
    /// Asynchronous factory expression passed via `asyncFactory:`.
    public let asyncFactoryExpr: ExprSyntax?
    /// Whether the async factory closure is throwing.
    public let asyncFactoryIsThrowing: Bool
    /// Whether concrete opt-in (`concrete: true`) was explicitly requested.
    public let concrete: Bool
    /// Explicit type expression passed as positional `Type.self`.
    public let typeExpr: ExprSyntax?
    /// Dependency key-path names passed via `with:`.
    public let dependencies: [String]

    /// Creates a parsed `@Provide` argument model.
    ///
    /// - Parameters:
    ///   - scope: Parsed scope value.
    ///   - scopeName: Raw scope name text.
    ///   - factoryExpr: Parsed factory expression.
    ///   - asyncFactoryExpr: Parsed async factory expression.
    ///   - asyncFactoryIsThrowing: Whether the async factory closure throws.
    ///   - concrete: Explicit concrete opt-in value.
    ///   - typeExpr: Positional type expression.
    ///   - dependencies: Parsed dependency names from `with:`.
    public init(
        scope: ProvideScope?,
        scopeName: String?,
        factoryExpr: ExprSyntax?,
        asyncFactoryExpr: ExprSyntax? = nil,
        asyncFactoryIsThrowing: Bool = false,
        concrete: Bool = false,
        typeExpr: ExprSyntax? = nil,
        dependencies: [String] = []
    ) {
        self.scope = scope
        self.scopeName = scopeName
        self.factoryExpr = factoryExpr
        self.asyncFactoryExpr = asyncFactoryExpr
        self.asyncFactoryIsThrowing = asyncFactoryIsThrowing
        self.concrete = concrete
        self.typeExpr = typeExpr
        self.dependencies = dependencies
    }
}

/// Lifetime policy for a `@SubContainer`-owned child container. Mirrors the
/// public `SubContainerScope` enum in the `InnoDI` product module so macro
/// expansion code and the CLI graph collector can share a single source of
/// truth for sub-container scope semantics.
///
/// Unlike `ProvideScope` there is no `.input` case: sub-containers are always
/// owned by their parent and replaced via `Overrides` rather than supplied
/// through the primary init.
public enum SubContainerScopeValue: String {
    /// Parent constructs and stores the child during parent initialization,
    /// then returns that cached instance on every subsequent access.
    case shared
    /// Every accessor read builds a fresh child container.
    case transient
}

/// Parsed arguments extracted from a single `@SubContainer` attribute.
public struct SubContainerAttributeInfo {
    /// Parsed scope value. `nil` when the author omitted the required
    /// `scope:` argument — the validator emits `sub.scope-required` in that
    /// case.
    public let scope: SubContainerScopeValue?
    /// Raw textual scope spelling as written so diagnostics can echo the
    /// exact source expression (for example, `.shared` or `someScope`).
    public let scopeName: String?
    /// Keypath member names passed via `with:`, in the order they appear.
    /// Used to re-map parent members when child `.input` parameter names do
    /// not match the parent side by name.
    public let dependencies: [String]
    /// Explicit child-input -> parent-member bindings passed via `bindings:`.
    /// Used when the child `.input` label differs from the parent member name.
    public let bindings: [SubContainerBindingArgument]

    /// Creates a parsed `@SubContainer` argument model.
    ///
    /// - Parameters:
    ///   - scope: Parsed scope value when the `scope:` expression matches a
    ///     supported `SubContainerScopeValue`.
    ///   - scopeName: Raw textual scope spelling or expression fragment.
    ///   - dependencies: Parsed dependency names from `with:`.
    public init(
        scope: SubContainerScopeValue?,
        scopeName: String?,
        dependencies: [String],
        bindings: [SubContainerBindingArgument]
    ) {
        self.scope = scope
        self.scopeName = scopeName
        self.dependencies = dependencies
        self.bindings = bindings
    }
}

/// Parsed explicit child-input -> parent-member remapping from a
/// `@SubContainer(bindings:)` tuple.
public struct SubContainerBindingArgument: Equatable, Sendable {
    /// Child `.input` member name taken from the tuple's `child:` keypath.
    public let childName: String
    /// Parent member name taken from the tuple's `parent:` keypath.
    public let parentName: String

    public init(childName: String, parentName: String) {
        self.childName = childName
        self.parentName = parentName
    }
}

/// Parsed arguments extracted from a single `@DIContainer` attribute.
public struct DIContainerAttributeInfo {
    /// Whether the container should be marked as graph root.
    public let root: Bool
    /// Whether DAG validation is enabled for this container.
    public let validateDAG: Bool
    /// Whether generated API is isolated to the main actor.
    public let mainActor: Bool

    /// Creates a parsed `@DIContainer` attribute model.
    ///
    /// - Parameters:
    ///   - root: Root flag.
    ///   - validateDAG: DAG validation flag.
    ///   - mainActor: Main actor isolation flag.
    public init(root: Bool, validateDAG: Bool, mainActor: Bool) {
        self.root = root
        self.validateDAG = validateDAG
        self.mainActor = mainActor
    }
}

/// Finds the first attribute whose base name matches `name`.
///
/// - Parameters:
///   - name: Attribute base name (for example, `"Provide"`).
///   - attributes: Attribute list to search.
/// - Returns: Matching `AttributeSyntax` when found; otherwise `nil`.
public func findAttribute(named name: String, in attributes: AttributeListSyntax?) -> AttributeSyntax? {
    guard let attributes else { return nil }
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        if attributeBaseName(attr.attributeName) == name {
            return attr
        }
    }
    return nil
}

package func findAttribute(
    named name: String,
    allowingQualifiedModules allowedQualifiedModules: Set<String>,
    in attributes: AttributeListSyntax?
) -> AttributeSyntax? {
    guard let attributes else { return nil }
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        if matchesAttribute(
            named: name,
            attributeName: attr.attributeName,
            allowingQualifiedModules: allowedQualifiedModules
        ) {
            return attr
        }
    }
    return nil
}

package func matchesAttribute(
    named name: String,
    attributeName: TypeSyntax,
    allowingQualifiedModules allowedQualifiedModules: Set<String>
) -> Bool {
    if let identifier = attributeName.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == name
    }
    guard let member = attributeName.as(MemberTypeSyntax.self),
          member.name.text == name,
          let baseIdentifier = member.baseType.as(IdentifierTypeSyntax.self) else {
        return false
    }
    return allowedQualifiedModules.contains(baseIdentifier.name.text)
}

package func findInnoDIAttribute(named name: String, in attributes: AttributeListSyntax?) -> AttributeSyntax? {
    findAttribute(
        named: name,
        allowingQualifiedModules: ["InnoDI"],
        in: attributes
    )
}

package func matchesInnoDIAttribute(named name: String, attributeName: TypeSyntax) -> Bool {
    matchesAttribute(
        named: name,
        attributeName: attributeName,
        allowingQualifiedModules: ["InnoDI"]
    )
}

private func attributeBaseName(_ type: TypeSyntax) -> String? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text
    }
    if let member = type.as(MemberTypeSyntax.self) {
        return member.name.text
    }
    return nil
}

public func parseProvideArguments(_ attribute: AttributeSyntax) -> ProvideArguments {
    var scopeName: String?
    var scope: ProvideScope?
    var factoryExpr: ExprSyntax?
    var asyncFactoryExpr: ExprSyntax?
    var asyncFactoryIsThrowing = false
    var concrete: Bool = false
    var typeExpr: ExprSyntax?
    var dependencies: [String] = []

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            if let label = argument.label?.text {
                if label == "factory" {
                    factoryExpr = argument.expression
                    continue
                }
                if label == "asyncFactory" {
                    asyncFactoryExpr = argument.expression
                    if let closure = argument.expression.as(ClosureExprSyntax.self) {
                        asyncFactoryIsThrowing = closure.signature?.effectSpecifiers?.throwsClause != nil
                    }
                    continue
                }
                if label == "concrete" {
                    if let value = parseBoolLiteral(argument.expression) {
                        concrete = value
                    }
                    continue
                }
                if label == "with" {
                    dependencies = parseKeyPathArrayArgument(argument.expression)
                    continue
                }
            } else {
                // Positional arguments
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self" {
                    // Type argument (e.g., APIClient.self)
                    typeExpr = memberAccess.base
                    continue
                }
                
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                     let name = memberAccess.declName.baseName.text
                     if let s = ProvideScope(rawValue: name) {
                         scopeName = name
                         scope = s
                     }
                }
            }
        }
    }

    if scopeName == nil {
        scopeName = ProvideScope.shared.rawValue
        scope = .shared
    }

    return ProvideArguments(
        scope: scope,
        scopeName: scopeName,
        factoryExpr: factoryExpr,
        asyncFactoryExpr: asyncFactoryExpr,
        asyncFactoryIsThrowing: asyncFactoryIsThrowing,
        concrete: concrete,
        typeExpr: typeExpr,
        dependencies: dependencies
    )
}

/// Extracts the final component names from a `with: [\.foo, \.bar]` style
/// array expression. Silently skips elements that are not `KeyPathExprSyntax`
/// or whose final component is not a property — macros intentionally ignore
/// exotic keypath shapes instead of failing to expand.
public func parseKeyPathArrayArgument(_ expression: ExprSyntax) -> [String] {
    guard let arrayExpr = expression.as(ArrayExprSyntax.self) else { return [] }
    var names: [String] = []
    for element in arrayExpr.elements {
        guard let property = finalKeyPathComponentName(from: element.expression) else {
            continue
        }
        names.append(property)
    }
    return names
}

/// Parses `bindings: [(child: \.foo, parent: \.bar)]` into semantic names.
public func parseSubContainerBindingsArgument(_ expression: ExprSyntax) -> [SubContainerBindingArgument] {
    guard let arrayExpr = expression.as(ArrayExprSyntax.self) else { return [] }
    var bindings: [SubContainerBindingArgument] = []

    for element in arrayExpr.elements {
        guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
            continue
        }

        var childName: String?
        var parentName: String?

        for tupleElement in tupleExpr.elements {
            guard let label = tupleElement.label?.text else { continue }
            switch label {
            case "child":
                childName = finalKeyPathComponentName(from: tupleElement.expression)
            case "parent":
                parentName = finalKeyPathComponentName(from: tupleElement.expression)
            default:
                continue
            }
        }

        if let childName, let parentName {
            bindings.append(
                SubContainerBindingArgument(
                    childName: childName,
                    parentName: parentName
                )
            )
        }
    }

    return bindings
}

/// Parses the full argument list of a single `@SubContainer` attribute.
/// Mirrors `parseProvideArguments` in shape so both attributes share
/// parsing patterns. Returns `nil`-scope when the required `scope:` argument
/// is missing; the validator surfaces the error.
public func parseSubContainerArguments(_ attribute: AttributeSyntax) -> SubContainerAttributeInfo {
    var scope: SubContainerScopeValue?
    var scopeName: String?
    var dependencies: [String] = []
    var bindings: [SubContainerBindingArgument] = []

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            switch label {
            case "scope":
                scopeName = argument.expression.trimmedDescription
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                    let name = memberAccess.declName.baseName.text
                    scope = SubContainerScopeValue(rawValue: name)
                }
            case "with":
                dependencies = parseKeyPathArrayArgument(argument.expression)
            case "bindings":
                bindings = parseSubContainerBindingsArgument(argument.expression)
            default:
                continue
            }
        }
    }

    return SubContainerAttributeInfo(
        scope: scope,
        scopeName: scopeName,
        dependencies: dependencies,
        bindings: bindings
    )
}

/// Finds and parses the first `@SubContainer` attribute in `attributes`.
///
/// - Parameter attributes: Attribute list attached to a declaration.
/// - Returns: Parsed `SubContainerAttributeInfo` when a `@SubContainer`
///   attribute is present; otherwise `nil`.
public func parseSubContainerAttribute(_ attributes: AttributeListSyntax?) -> SubContainerAttributeInfo? {
    guard let attribute = findInnoDIAttribute(named: "SubContainer", in: attributes) else {
        return nil
    }
    return parseSubContainerArguments(attribute)
}

public func parseProvideAttribute(_ attributes: AttributeListSyntax?) -> ProvideArguments? {
    guard let attribute = findInnoDIAttribute(named: "Provide", in: attributes) else {
        return nil
    }
    return parseProvideArguments(attribute)
}

public func parseBoolLiteral(_ expr: ExprSyntax) -> Bool? {
    if let literal = expr.as(BooleanLiteralExprSyntax.self) {
        return literal.literal.text == "true"
    }
    if let reference = expr.as(DeclReferenceExprSyntax.self) {
        if reference.baseName.text == "true" { return true }
        if reference.baseName.text == "false" { return false }
    }
    return nil
}

private func finalKeyPathComponentName(from expression: ExprSyntax) -> String? {
    guard let keyPath = expression.as(KeyPathExprSyntax.self) else {
        return nil
    }
    return keyPath.components.last?
        .component.as(KeyPathPropertyComponentSyntax.self)?
        .declName.baseName.text
}

public func parseDIContainerAttribute(_ attributes: AttributeListSyntax?) -> DIContainerAttributeInfo? {
    guard let attr = findInnoDIAttribute(named: "DIContainer", in: attributes) else { return nil }

    var root = false
    var validateDAG = true
    var mainActor = false

    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            if label == "root", let value = parseBoolLiteral(argument.expression) {
                root = value
            }
            if label == "validateDAG", let value = parseBoolLiteral(argument.expression) {
                validateDAG = value
            }
            if label == "mainActor", let value = parseBoolLiteral(argument.expression) {
                mainActor = value
            }
        }
    }

    return DIContainerAttributeInfo(root: root, validateDAG: validateDAG, mainActor: mainActor)
}
