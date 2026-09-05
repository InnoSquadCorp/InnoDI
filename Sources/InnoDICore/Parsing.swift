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

/// Controls when a shared provider runs its construction source.
public enum ProvideInitializationValue: String, Equatable, Sendable {
    case eager
    case onDemand
}

/// Semantic source of a container input.
///
/// Container inputs are supplied when the container itself is constructed.
/// Assisted inputs are supplied later through a child-owned factory call.
public enum InputKindValue: String, Equatable, Sendable {
    case container
    case assisted
}

/// Normalized 6.0 role for a dependency container.
public enum DIContainerRoleValue: String, Equatable, Sendable {
    case local
    case component
    case root
}

/// Parse state for macro arguments that must be literal Bool expressions.
public enum BoolArgumentParseState: Equatable, Sendable {
    /// The labeled argument did not appear in source.
    case omitted
    /// A literal `true` or `false` was parsed.
    case parsed(Bool)
    /// The argument appeared but was not a literal Bool the macro can evaluate.
    case invalid

    public var value: Bool? {
        if case let .parsed(value) = self {
            return value
        }
        return nil
    }

    public var isInvalid: Bool {
        if case .invalid = self {
            return true
        }
        return false
    }

    public var hasArgument: Bool {
        switch self {
        case .omitted:
            return false
        case .parsed, .invalid:
            return true
        }
    }
}

/// Parse state for `with:` key-path array arguments.
public enum KeyPathArrayArgumentParseState: Equatable, Sendable {
    /// The labeled argument did not appear in source.
    case omitted
    /// A literal array was fully parsed. The list may be empty.
    case parsed([String])
    /// The argument appeared but was not a fully parseable literal key-path array.
    case invalid

    public var dependencies: [String] {
        if case let .parsed(dependencies) = self {
            return dependencies
        }
        return []
    }

    public var isInvalid: Bool {
        if case .invalid = self {
            return true
        }
        return false
    }

    public var hasArgument: Bool {
        switch self {
        case .omitted:
            return false
        case .parsed, .invalid:
            return true
        }
    }
}

/// Parsed arguments extracted from a single `@Provide` attribute.
public struct ProvideArguments {
    /// Parsed scope value (`.shared`, `.input`, `.transient`) when available.
    public let scope: ProvideScope?
    /// Raw textual scope name. Invalid explicit expressions are preserved so
    /// callers can distinguish them from an omitted scope.
    public let scopeName: String?
    /// Explicit scope expression, or `nil` when the default `.shared` scope
    /// was omitted at the call site.
    public let scopeExpr: ExprSyntax?
    /// Shared-provider construction timing.
    public let initialization: ProvideInitializationValue?
    /// Raw initialization spelling for diagnostics.
    public let initializationName: String?
    /// Explicit initialization expression, when present.
    public let initializationExpr: ExprSyntax?
    /// Factory expression passed via `factory:`.
    public let factoryExpr: ExprSyntax?
    /// Asynchronous factory expression passed via `asyncFactory:`.
    public let asyncFactoryExpr: ExprSyntax?
    /// Whether the async factory closure is throwing.
    public let asyncFactoryIsThrowing: Bool
    /// Whether a function-valued `.input` hidden behind a typealias must be
    /// emitted as an escaping initializer parameter.
    public let escaping: Bool
    /// Literal parse state for `escaping:`.
    public let escapingParseState: BoolArgumentParseState
    /// Explicit type expression passed as positional `Type.self`.
    public let typeExpr: ExprSyntax?
    /// Dependency key-path names passed via `with:`.
    public let dependencies: [String]
    /// Initializer labels paired with `dependencies`. Ordinary `@Provide`
    /// values use the dependency name as the label. `@SubContainerFactory`
    /// keeps the child input label separate from the parent member name.
    public let dependencyLabels: [String]
    /// Literal parse state for `with:`.
    public let dependenciesParseState: KeyPathArrayArgumentParseState
    /// Input timing parsed from `@Input`. Legacy `@Provide(.input)` values are
    /// normalized to `.container`.
    public let inputKind: InputKindValue
    /// Child container expression from `@SubContainerFactory(Child.self, ...)`.
    /// `nil` for ordinary providers and inputs.
    public let assistedFactoryChildType: ExprSyntax?
    /// Whether this provider is the public deterministic collection-binding
    /// spelling. Contributors are carried by `dependencies` in source order.
    public let isMultibinding: Bool

    /// Creates a parsed `@Provide` argument model.
    ///
    /// - Parameters:
    ///   - scope: Parsed scope value.
    ///   - scopeName: Raw scope name text.
    ///   - scopeExpr: Explicit scope expression, when supplied.
    ///   - factoryExpr: Parsed factory expression.
    ///   - asyncFactoryExpr: Parsed async factory expression.
    ///   - asyncFactoryIsThrowing: Whether the async factory closure throws.
    ///   - escaping: Explicit escaping-input opt-in value.
    ///   - typeExpr: Positional type expression.
    ///   - dependencies: Parsed dependency names from `with:`.
    public init(
        scope: ProvideScope?,
        scopeName: String?,
        scopeExpr: ExprSyntax? = nil,
        initialization: ProvideInitializationValue? = .eager,
        initializationName: String? = ProvideInitializationValue.eager.rawValue,
        initializationExpr: ExprSyntax? = nil,
        factoryExpr: ExprSyntax?,
        asyncFactoryExpr: ExprSyntax? = nil,
        asyncFactoryIsThrowing: Bool = false,
        escaping: Bool = false,
        escapingParseState: BoolArgumentParseState? = nil,
        typeExpr: ExprSyntax? = nil,
        dependencies: [String] = [],
        dependencyLabels: [String]? = nil,
        dependenciesParseState: KeyPathArrayArgumentParseState? = nil,
        inputKind: InputKindValue = .container,
        assistedFactoryChildType: ExprSyntax? = nil,
        isMultibinding: Bool = false
    ) {
        self.scope = scope
        self.scopeName = scopeName
        self.scopeExpr = scopeExpr
        self.initialization = initialization
        self.initializationName = initializationName
        self.initializationExpr = initializationExpr
        self.factoryExpr = factoryExpr
        self.asyncFactoryExpr = asyncFactoryExpr
        self.asyncFactoryIsThrowing = asyncFactoryIsThrowing
        self.escaping = escaping
        self.escapingParseState = escapingParseState ?? (escaping ? .parsed(true) : .omitted)
        self.typeExpr = typeExpr
        self.dependencies = dependencies
        self.dependencyLabels = dependencyLabels ?? dependencies
        self.dependenciesParseState = dependenciesParseState ?? (dependencies.isEmpty ? .omitted : .parsed(dependencies))
        self.inputKind = inputKind
        self.assistedFactoryChildType = assistedFactoryChildType
        self.isMultibinding = isMultibinding
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

/// Source spelling used for `@SubContainer` same-name wiring.
public enum SubContainerSameNameWiringLabel: String, Equatable, Sendable {
    /// Key-path based same-name wiring (`with: [\.foo]`).
    case with
}

/// Parse state for `@SubContainer` same-name wiring.
///
/// The macro must distinguish omitted wiring from an explicitly empty literal
/// array. It also must not silently treat runtime variables or partially
/// unparseable arrays as an empty subset.
///
public enum SubContainerSameNameWiringParseState: Equatable, Sendable {
    /// `with:` did not appear in the source.
    case omitted
    /// A literal array was fully parsed. The dependency list may be empty.
    case parsed(label: SubContainerSameNameWiringLabel, dependencies: [String])
    /// `with:` appeared but was not a fully parseable literal array.
    case invalid(label: SubContainerSameNameWiringLabel)
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
    /// Parent member names passed via `with:`, in the order they appear.
    /// These select the same-named inputs that are forwarded to the child.
    /// Use `bindings:` when child input names differ from parent names.
    public let dependencies: [String]
    /// Whether the attribute contains the `with:` keypath argument.
    public let hasWithDependencies: Bool
    /// Literal parse state for `with:`.
    public let sameNameWiring: SubContainerSameNameWiringParseState
    /// Explicit child-input -> parent-member bindings passed via `bindings:`.
    /// Used when the child `.input` label differs from the parent member name.
    public let bindings: [SubContainerBindingArgument]
    /// Literal parse state for `bindings:`.
    public let bindingsParseState: SubContainerBindingsParseState

    /// Creates a parsed `@SubContainer` argument model.
    ///
    /// - Parameters:
    ///   - scope: Parsed scope value when the `scope:` expression matches a
    ///     supported `SubContainerScopeValue`.
    ///   - scopeName: Raw textual scope spelling or expression fragment.
    ///   - dependencies: Parsed dependency names from `with:`.
    ///   - hasWithDependencies: Whether `with:` appeared in the source.
    public init(
        scope: SubContainerScopeValue?,
        scopeName: String?,
        dependencies: [String],
        hasWithDependencies: Bool = false,
        sameNameWiring: SubContainerSameNameWiringParseState = .omitted,
        bindings: [SubContainerBindingArgument],
        bindingsParseState: SubContainerBindingsParseState? = nil
    ) {
        self.scope = scope
        self.scopeName = scopeName
        self.dependencies = dependencies
        self.hasWithDependencies = hasWithDependencies
        self.sameNameWiring = sameNameWiring
        self.bindings = bindings
        self.bindingsParseState = bindingsParseState ?? (bindings.isEmpty ? .omitted : .parsed(bindings))
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

/// Parse state for `@SubContainer(bindings:)`.
public enum SubContainerBindingsParseState: Equatable, Sendable {
    /// `bindings:` did not appear in source.
    case omitted
    /// A literal bindings array was fully parsed. The list may be empty.
    case parsed([SubContainerBindingArgument])
    /// `bindings:` appeared but was not a fully parseable literal tuple array.
    case invalid

    public var bindings: [SubContainerBindingArgument] {
        if case let .parsed(bindings) = self {
            return bindings
        }
        return []
    }

    public var isInvalid: Bool {
        if case .invalid = self {
            return true
        }
        return false
    }

    public var hasArgument: Bool {
        switch self {
        case .omitted:
            return false
        case .parsed, .invalid:
            return true
        }
    }
}

/// Parsed arguments extracted from a single `@DIContainer` attribute.
public struct DIContainerAttributeInfo {
    /// 6.0 container role. Legacy marker macros normalize into the same
    /// semantic model in their respective validators.
    public let role: DIContainerRoleValue
    /// Whether the `role:` expression is one of InnoDI's named role tokens.
    public let roleArgumentIsValid: Bool
    /// Whether the container should be marked as graph root.
    public let root: Bool
    /// Literal parse state for `root:`.
    public let rootParseState: BoolArgumentParseState
    /// Whether DAG validation is enabled for this container.
    public let validateDAG: Bool
    /// Literal parse state for `validateDAG:`.
    public let validateDAGParseState: BoolArgumentParseState
    /// Whether generated API is isolated to the main actor.
    public let mainActor: Bool
    /// Literal parse state for `mainActor:`.
    public let mainActorParseState: BoolArgumentParseState

    /// Creates a parsed `@DIContainer` attribute model.
    ///
    /// - Parameters:
    ///   - root: Root flag.
    ///   - validateDAG: DAG validation flag.
    ///   - mainActor: Main actor isolation flag.
    public init(
        role: DIContainerRoleValue = .local,
        roleArgumentIsValid: Bool = true,
        root: Bool,
        validateDAG: Bool,
        mainActor: Bool,
        rootParseState: BoolArgumentParseState = .omitted,
        validateDAGParseState: BoolArgumentParseState = .omitted,
        mainActorParseState: BoolArgumentParseState = .omitted
    ) {
        self.role = role
        self.roleArgumentIsValid = roleArgumentIsValid
        self.root = root || role == .root
        self.rootParseState = rootParseState
        self.validateDAG = validateDAG
        self.validateDAGParseState = validateDAGParseState
        self.mainActor = mainActor
        self.mainActorParseState = mainActorParseState
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

private func isSupportedProvideScopeReference(_ expression: MemberAccessExprSyntax) -> Bool {
    guard let base = expression.base else {
        return true
    }

    switch base.trimmedDescription {
    case "DIScope", "InnoDI.DIScope":
        return true
    default:
        return false
    }
}

public func parseProvideArguments(_ attribute: AttributeSyntax) -> ProvideArguments {
    let managedAttributeName = attributeBaseName(attribute.attributeName)
    if managedAttributeName == "Input" {
        return parseInputArguments(attribute)
    }
    if managedAttributeName == "SubContainerFactory" {
        return parseSubContainerFactoryArguments(attribute)
    }
    if managedAttributeName == "Multibinding" {
        return parseMultibindingArguments(attribute)
    }
    var scopeName: String?
    var scope: ProvideScope?
    var scopeExpr: ExprSyntax?
    var factoryExpr: ExprSyntax?
    var initialization: ProvideInitializationValue? = .eager
    var initializationName: String? = ProvideInitializationValue.eager.rawValue
    var initializationExpr: ExprSyntax?
    var asyncFactoryExpr: ExprSyntax?
    var asyncFactoryIsThrowing = false
    var escaping: Bool = false
    var escapingParseState: BoolArgumentParseState = .omitted
    var typeExpr: ExprSyntax?
    var dependencies: [String] = []
    var dependenciesParseState: KeyPathArrayArgumentParseState = .omitted

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            if let label = argument.label?.text {
                if label == "factory" {
                    factoryExpr = argument.expression
                    continue
                }
                if label == "initialization" {
                    initializationExpr = argument.expression
                    initializationName = argument.expression.trimmedDescription
                    if let member = argument.expression.as(
                        MemberAccessExprSyntax.self
                    ) {
                        let name = member.declName.baseName.text
                        initializationName = name
                        initialization = ProvideInitializationValue(
                            rawValue: name
                        )
                    } else {
                        initialization = nil
                    }
                    continue
                }
                if label == "asyncFactory" {
                    asyncFactoryExpr = argument.expression
                    if let closure = argument.expression.as(ClosureExprSyntax.self) {
                        asyncFactoryIsThrowing = closure.signature?.effectSpecifiers?.throwsClause != nil
                    }
                    continue
                }
                if label == "escaping" {
                    escapingParseState = parseBoolArgument(argument.expression)
                    if let value = escapingParseState.value {
                        escaping = value
                    }
                    continue
                }
                if label == "with" {
                    dependenciesParseState = parseQualifiedKeyPathArrayArgumentState(
                        argument.expression
                    )
                    dependencies = dependenciesParseState.dependencies
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

                // The first non-Type.self positional expression is the scope.
                // Preserve unsupported or dynamic spellings instead of
                // confusing an explicit value with an omitted `.shared`.
                if scopeExpr == nil {
                    scopeExpr = argument.expression
                    scopeName = argument.expression.trimmedDescription

                    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                        let name = memberAccess.declName.baseName.text
                        if isSupportedProvideScopeReference(memberAccess) {
                            scopeName = name
                            scope = ProvideScope(rawValue: name)
                        }
                    }
                }
            }
        }
    }

    if scopeExpr == nil {
        scopeName = ProvideScope.shared.rawValue
        scope = .shared
    }

    return ProvideArguments(
        scope: scope,
        scopeName: scopeName,
        scopeExpr: scopeExpr,
        initialization: initialization,
        initializationName: initializationName,
        initializationExpr: initializationExpr,
        factoryExpr: factoryExpr,
        asyncFactoryExpr: asyncFactoryExpr,
        asyncFactoryIsThrowing: asyncFactoryIsThrowing,
        escaping: escaping,
        escapingParseState: escapingParseState,
        typeExpr: typeExpr,
        dependencies: dependencies,
        dependenciesParseState: dependenciesParseState
    )
}

/// Parses an ordered public multibinding declaration into the provider IR.
/// The collection behaves as a synchronous transient provider: each read
/// resolves contributors through their own accessors, so their individual
/// lifetime and override semantics remain authoritative.
public func parseMultibindingArguments(
    _ attribute: AttributeSyntax
) -> ProvideArguments {
    var state: KeyPathArrayArgumentParseState = .omitted
    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
       arguments.count == 1,
       let argument = arguments.first,
       argument.label == nil {
        state = parseQualifiedKeyPathArrayArgumentState(argument.expression)
    } else if attribute.arguments != nil {
        state = .invalid
    }

    return ProvideArguments(
        scope: .transient,
        scopeName: ProvideScope.transient.rawValue,
        factoryExpr: nil,
        dependencies: state.dependencies,
        dependenciesParseState: state,
        isMultibinding: true
    )
}

/// Parses the parent-owned assisted-factory declaration into the existing
/// provider construction IR. The generated provider is shared in the parent;
/// each factory call still creates a fresh child container instance.
public func parseSubContainerFactoryArguments(
    _ attribute: AttributeSyntax
) -> ProvideArguments {
    var childType: ExprSyntax?
    var factoryType: ExprSyntax?
    var bindingsState: SubContainerBindingsParseState = .omitted

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            if argument.label?.text == "bindings" {
                bindingsState = parseSubContainerBindingsArgumentState(
                    argument.expression
                )
                continue
            }
            guard argument.label == nil,
                  let member = argument.expression.as(
                    MemberAccessExprSyntax.self
                  ),
                  member.declName.baseName.text == "self",
                  let base = member.base else {
                continue
            }
            childType = base
            factoryType = ExprSyntax(
                MemberAccessExprSyntax(
                    base: base,
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(
                        baseName: .identifier("AssistedFactory")
                    )
                )
            )
        }
    }

    let bindings = bindingsState.bindings
    let dependencyState: KeyPathArrayArgumentParseState
    switch bindingsState {
    case .omitted:
        dependencyState = .omitted
    case .invalid:
        dependencyState = .invalid
    case .parsed:
        dependencyState = .parsed(bindings.map(\.parentName))
    }

    return ProvideArguments(
        scope: .shared,
        scopeName: ProvideScope.shared.rawValue,
        factoryExpr: nil,
        typeExpr: factoryType,
        dependencies: bindings.map(\.parentName),
        dependencyLabels: bindings.map(\.childName),
        dependenciesParseState: dependencyState,
        assistedFactoryChildType: childType
    )
}

/// Parses the 6.0 `@Input` spelling into the existing provider IR. This keeps
/// initialization, storage, hierarchy, and graph consumers on one normalized
/// model while retaining the assisted/container distinction.
public func parseInputArguments(_ attribute: AttributeSyntax) -> ProvideArguments {
    var kind: InputKindValue = .container
    var escaping = false
    var escapingParseState: BoolArgumentParseState = .omitted

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            if argument.label?.text == "escaping" {
                escapingParseState = parseBoolArgument(argument.expression)
                if let value = escapingParseState.value {
                    escaping = value
                }
                continue
            }
            guard argument.label == nil,
                  let member = argument.expression.as(MemberAccessExprSyntax.self) else {
                continue
            }
            let name = member.declName.baseName.text
            if let parsed = InputKindValue(rawValue: name) {
                kind = parsed
            }
        }
    }

    return ProvideArguments(
        scope: .input,
        scopeName: ProvideScope.input.rawValue,
        factoryExpr: nil,
        escaping: escaping,
        escapingParseState: escapingParseState,
        inputKind: kind
    )
}

/// `@Provide` is declared with `[AnyKeyPath]`, so Swift cannot infer the root of
/// `\.member`. InnoDI 5.0 requires the canonical `\Self.member` spelling.
/// Unlike a bare container identifier, `Self` cannot be shadowed by a nested
/// typealias that silently changes the key path's semantic root while codegen
/// still resolves the final member name against the enclosing container.
private func parseQualifiedKeyPathArrayArgumentState(
    _ expression: ExprSyntax
) -> KeyPathArrayArgumentParseState {
    guard let arrayExpr = expression.as(ArrayExprSyntax.self) else {
        return .invalid
    }
    var names: [String] = []
    for element in arrayExpr.elements {
        guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
              keyPath.root?.trimmedDescription == "Self",
              keyPath.components.count == 1,
              let property = finalKeyPathComponentName(from: element.expression) else {
            return .invalid
        }
        names.append(property)
    }
    return .parsed(names)
}

/// Extracts the final component names from a `with: [\.foo, \.bar]` style
/// array expression. Returns `[]` when the expression is invalid; callers that
/// need to distinguish invalid from explicit empty arrays should use
/// `parseKeyPathArrayArgumentState(_:)`.
public func parseKeyPathArrayArgument(_ expression: ExprSyntax) -> [String] {
    parseKeyPathArrayArgumentState(expression).dependencies
}

/// Strictly parses a key-path literal array and preserves invalid state.
public func parseKeyPathArrayArgumentState(_ expression: ExprSyntax) -> KeyPathArrayArgumentParseState {
    guard let arrayExpr = expression.as(ArrayExprSyntax.self) else { return .invalid }
    var names: [String] = []
    for element in arrayExpr.elements {
        guard let property = finalKeyPathComponentName(from: element.expression) else {
            return .invalid
        }
        names.append(property)
    }
    return .parsed(names)
}

/// Strictly parses a `with: [\.foo, \.bar]` array for `@SubContainer`.
/// Returns `nil` when the expression is not a literal array or any element is
/// not a simple key path whose final component is a property.
public func parseStrictKeyPathArrayArgument(_ expression: ExprSyntax) -> [String]? {
    switch parseKeyPathArrayArgumentState(expression) {
    case let .parsed(dependencies):
        return dependencies
    case .omitted, .invalid:
        return nil
    }
}

/// Parses `bindings: [(child: \.foo, parent: \.bar)]` into semantic names.
public func parseSubContainerBindingsArgument(_ expression: ExprSyntax) -> [SubContainerBindingArgument] {
    parseSubContainerBindingsArgumentState(expression).bindings
}

/// Strictly parses `bindings:` and preserves invalid state.
public func parseSubContainerBindingsArgumentState(_ expression: ExprSyntax) -> SubContainerBindingsParseState {
    guard let arrayExpr = expression.as(ArrayExprSyntax.self) else { return .invalid }
    var bindings: [SubContainerBindingArgument] = []

    for element in arrayExpr.elements {
        guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
            return .invalid
        }

        var childName: String?
        var parentName: String?

        guard tupleExpr.elements.count == 2 else {
            return .invalid
        }

        for tupleElement in tupleExpr.elements {
            guard let label = tupleElement.label?.text else {
                return .invalid
            }
            switch label {
            case "child":
                guard childName == nil else {
                    return .invalid
                }
                guard let parsed = finalKeyPathComponentName(from: tupleElement.expression) else {
                    return .invalid
                }
                childName = parsed
            case "parent":
                guard parentName == nil else {
                    return .invalid
                }
                guard let parsed = finalKeyPathComponentName(from: tupleElement.expression) else {
                    return .invalid
                }
                parentName = parsed
            default:
                return .invalid
            }
        }

        guard let childName, let parentName else {
            return .invalid
        }

        bindings.append(
            SubContainerBindingArgument(
                childName: childName,
                parentName: parentName
            )
        )
    }

    return .parsed(bindings)
}

/// Parses the full argument list of a single `@SubContainer` attribute.
/// Mirrors `parseProvideArguments` in shape so both attributes share
/// parsing patterns. Returns `nil`-scope when the required `scope:` argument
/// is missing; the validator surfaces the error.
public func parseSubContainerArguments(_ attribute: AttributeSyntax) -> SubContainerAttributeInfo {
    var scope: SubContainerScopeValue?
    var scopeName: String?
    var dependencies: [String] = []
    var hasWithDependencies = false
    var sameNameWiring: SubContainerSameNameWiringParseState = .omitted
    var bindings: [SubContainerBindingArgument] = []
    var bindingsParseState: SubContainerBindingsParseState = .omitted

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
                hasWithDependencies = true
                if let parsedDependencies = parseStrictKeyPathArrayArgument(argument.expression) {
                    dependencies = parsedDependencies
                    sameNameWiring = .parsed(label: .with, dependencies: parsedDependencies)
                } else {
                    dependencies = []
                    sameNameWiring = .invalid(label: .with)
                }
            case "bindings":
                bindingsParseState = parseSubContainerBindingsArgumentState(argument.expression)
                bindings = bindingsParseState.bindings
            default:
                continue
            }
        }
    }

    return SubContainerAttributeInfo(
        scope: scope,
        scopeName: scopeName,
        dependencies: dependencies,
        hasWithDependencies: hasWithDependencies,
        sameNameWiring: sameNameWiring,
        bindings: bindings,
        bindingsParseState: bindingsParseState
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
    guard let attribute = findManagedProviderAttribute(in: attributes) else {
        return nil
    }
    return parseProvideArguments(attribute)
}

/// Finds the first public attribute that participates in provider storage.
public func findManagedProviderAttribute(
    in attributes: AttributeListSyntax?
) -> AttributeSyntax? {
    findInnoDIAttribute(named: "Provide", in: attributes)
        ?? findInnoDIAttribute(named: "Input", in: attributes)
        ?? findInnoDIAttribute(named: "SubContainerFactory", in: attributes)
        ?? findInnoDIAttribute(named: "Multibinding", in: attributes)
}

/// Finds all provider-storage roles in source order. The roles are mutually
/// exclusive and duplicates are diagnosed by their consumers.
public func findManagedProviderAttributes(
    in attributes: AttributeListSyntax?
) -> [AttributeSyntax] {
    guard let attributes else { return [] }
    return attributes.compactMap { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return nil }
        let name = attributeBaseName(attribute.attributeName)
        guard name == "Provide"
            || name == "Input"
            || name == "SubContainerFactory"
            || name == "Multibinding" else { return nil }
        if let member = attribute.attributeName.as(MemberTypeSyntax.self),
           member.baseType.trimmedDescription != "InnoDI" {
            return nil
        }
        return attribute
    }
}

/// Returns the element type when `type` is written as an array.
public func multibindingElementType(_ type: TypeSyntax) -> TypeSyntax? {
    type.as(ArrayTypeSyntax.self)?.element
}

public func parseBoolLiteral(_ expr: ExprSyntax) -> Bool? {
    parseBoolArgument(expr).value
}

/// Parses a macro Bool option and preserves whether a non-literal was supplied.
public func parseBoolArgument(_ expr: ExprSyntax) -> BoolArgumentParseState {
    if let literal = expr.as(BooleanLiteralExprSyntax.self) {
        return .parsed(literal.literal.text == "true")
    }
    if let reference = expr.as(DeclReferenceExprSyntax.self) {
        if reference.baseName.text == "true" { return .parsed(true) }
        if reference.baseName.text == "false" { return .parsed(false) }
    }
    return .invalid
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
    guard let attr = findDIContainerAttribute(in: attributes) else {
        return nil
    }

    var root = false
    var validateDAG = true
    var mainActor = false
    var rootParseState: BoolArgumentParseState = .omitted
    var validateDAGParseState: BoolArgumentParseState = .omitted
    var mainActorParseState: BoolArgumentParseState = .omitted
    var role: DIContainerRoleValue = .local
    let isRoleAttribute = attributeBaseName(attr.attributeName) == "DIContainerRole"
    var roleArgumentIsValid = !isRoleAttribute

    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            guard let label = argument.label?.text else {
                if let member = argument.expression.as(MemberAccessExprSyntax.self),
                   let parsed = DIContainerRoleValue(
                    rawValue: member.declName.baseName.text
                   ) {
                    role = parsed
                }
                continue
            }
            if label == "role" {
                if let member = argument.expression.as(MemberAccessExprSyntax.self),
                   isSupportedContainerRoleReference(member),
                   let parsed = DIContainerRoleValue(
                    rawValue: member.declName.baseName.text
                   ) {
                    role = parsed
                    roleArgumentIsValid = true
                } else {
                    roleArgumentIsValid = false
                }
            }
            if label == "root" {
                rootParseState = parseBoolArgument(argument.expression)
                if let value = rootParseState.value {
                    root = value
                }
            }
            if label == "validateDAG" {
                validateDAGParseState = parseBoolArgument(argument.expression)
                if let value = validateDAGParseState.value {
                    validateDAG = value
                }
            }
            if label == "mainActor" {
                mainActorParseState = parseBoolArgument(argument.expression)
                if let value = mainActorParseState.value {
                    mainActor = value
                }
            }
        }
    }

    return DIContainerAttributeInfo(
        role: role,
        roleArgumentIsValid: roleArgumentIsValid,
        root: root,
        validateDAG: validateDAG,
        mainActor: mainActor,
        rootParseState: rootParseState,
        validateDAGParseState: validateDAGParseState,
        mainActorParseState: mainActorParseState
    )
}

private func isSupportedContainerRoleReference(
    _ expression: MemberAccessExprSyntax
) -> Bool {
    guard let base = expression.base else { return false }
    switch base.trimmedDescription {
    case "ContainerRole", "InnoDI.ContainerRole":
        return true
    default:
        return false
    }
}

/// Finds either the compatibility or role-based public container attribute.
public func findDIContainerAttribute(
    in attributes: AttributeListSyntax?
) -> AttributeSyntax? {
    findInnoDIAttribute(named: "DIContainer", in: attributes)
        ?? findInnoDIAttribute(named: "DIContainerRole", in: attributes)
}
