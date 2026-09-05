import InnoDICore

/// Revalidates ordered collection bindings from the whole-source snapshot.
/// This keeps malformed or stale macro expansion inputs from bypassing the
/// build plugin's serialized contract.
func validateMultibindings(
    _ multibindings: [SemanticMultibindingRecord],
    containersByPath: [String: SemanticContainerRecord]
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    for multibinding in multibindings {
        guard let container = containersByPath[multibinding.containerPath]
        else { continue }
        if let invalid = multibinding.invalidContributorsLocation {
            issues.append(multibindingIssue(
                code: "multibinding.invalid-contributors",
                message: "@Multibinding requires one literal array of canonical \\Self.member key paths.",
                record: multibinding,
                location: invalid,
                remediation: "Use a nonempty literal such as @Multibinding([\\Self.auth, \\Self.logging])."
            ))
            continue
        }
        guard multibinding.elementType != nil else {
            issues.append(multibindingIssue(
                code: "multibinding.collection-type-required",
                message: "@Multibinding member '\(multibinding.memberName)' must declare an array type.",
                record: multibinding,
                remediation: "Declare the member as [Element], where every contributor exposes Element."
            ))
            continue
        }
        var seen: Set<String> = []
        for contributor in multibinding.contributors {
            if !seen.insert(contributor.name).inserted {
                issues.append(multibindingIssue(
                    code: "multibinding.duplicate-contributor",
                    message: "Contributor '\(contributor.name)' appears more than once in @Multibinding member '\(multibinding.memberName)'.",
                    record: multibinding,
                    location: contributor.location,
                    remediation: "Keep each contributor exactly once; array order remains output order."
                ))
                continue
            }
            guard contributor.name != multibinding.memberName,
                  let provider = container.managedMembers[contributor.name]
            else {
                issues.append(multibindingIssue(
                    code: "multibinding.unknown-contributor",
                    message: "Contributor '\(contributor.name)' does not name another direct managed dependency in '\(container.displayName)'.",
                    record: multibinding,
                    location: contributor.location,
                    remediation: "Use a key path to a direct @Provide or @Input member."
                ))
                continue
            }
            if provider.isAsync {
                issues.append(multibindingIssue(
                    code: "multibinding.async-contributor",
                    message: "Synchronous @Multibinding member '\(multibinding.memberName)' cannot collect async contributor '\(contributor.name)'.",
                    record: multibinding,
                    location: contributor.location,
                    remediation: "Use a synchronous contributor or construct the async collection explicitly."
                ))
                continue
            }
            // Swift's generated array expression is the authoritative
            // assignability check. Build support intentionally does not infer
            // Swift subtyping from written type strings.
        }
    }
    return issues
}

private func multibindingIssue(
    code: String,
    message: String,
    record: SemanticMultibindingRecord,
    location: ValidationIssueLocation? = nil,
    remediation: String
) -> ValidationIssue {
    ValidationIssue(
        code: code,
        severity: .error,
        message: message,
        location: location ?? record.location,
        remediation: remediation,
        metadata: [
            "containerPath": record.containerPath,
            "multibindingMemberName": record.memberName,
        ]
    )
}

/// Validates `@SubContainer(bindings:)` records after source collection and
/// semantic path resolution have completed.
func validateSubContainerBindings(
    _ subContainers: [SemanticSubContainerRecord],
    semanticResolver: SemanticResolverIndex,
    containerInputsByPath: [String: SemanticContainerRecord],
    containerCandidatePaths: Set<String>
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    for subContainer in subContainers {
        if let invalidBindingsLocation = subContainer.invalidBindingsLocation {
            issues.append(
                makeInvalidBindingsIssue(
                    for: subContainer,
                    location: invalidBindingsLocation
                )
            )
            continue
        }

        guard let childReference = subContainer.childReference else {
            continue
        }

        let resolution = semanticResolver.resolvePath(
            for: childReference,
            candidatePaths: containerCandidatePaths
        )
        guard resolution.state == .resolved,
              let childPath = resolution.resolvedPath,
              let childContainer = containerInputsByPath[childPath] else {
            continue
        }

        for binding in subContainer.bindings
            where !childContainer.inputMembers.contains(binding.childInputName) {
            issues.append(
                ValidationIssue(
                    code: MacroBuildDiagnosticContract
                        .subUnknownChildInputCode,
                    severity: .error,
                    message: MacroBuildDiagnosticContract
                        .subUnknownChildInputMessage(
                            memberName: subContainer.memberName,
                            childInputName: binding.childInputName,
                            childContainerName: childContainer.displayName
                        ),
                    location: binding.childLocation,
                    notes: [
                        ValidationIssueNote(
                            message: "child container '\(childContainer.path)' is declared here.",
                            location: childContainer.location
                        )
                    ],
                    remediation: "Rename the child keypath in bindings:, or add a matching @Input member to '\(childContainer.displayName)'.",
                    metadata: [
                        "childContainerPath": childContainer.path,
                        "parentContainerPath": subContainer.parentContainerPath
                    ]
                )
            )
        }
    }

    return issues
}

/// Validates the child-to-parent contract of `@SubContainerFactory` after all
/// files in the target have been collected. This is the authoritative gate for
/// same-target declarations that attached macros cannot inspect across files.
func validateAssistedFactoryBindings(
    _ factories: [SemanticAssistedFactoryRecord],
    semanticResolver: SemanticResolverIndex,
    containersByPath: [String: SemanticContainerRecord],
    containerCandidatePaths: Set<String>
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    for factory in factories {
        if let invalid = factory.invalidBindingsLocation {
            issues.append(ValidationIssue(
                code: "assisted-factory.invalid-bindings",
                severity: .error,
                message: "@SubContainerFactory member '\(factory.memberName)' requires a literal bindings: array of (child: key path, parent: key path) tuples.",
                location: invalid,
                remediation: "Bind every ordinary child @Input exactly once with literal child and parent key paths."
            ))
            continue
        }
        guard let childReference = factory.childReference else { continue }
        let resolution = semanticResolver.resolvePath(
            for: childReference,
            candidatePaths: containerCandidatePaths
        )
        guard resolution.state == .resolved,
              let childPath = resolution.resolvedPath,
              let child = containersByPath[childPath] else {
            continue
        }

        if child.assistedInputMembers.isEmpty {
            issues.append(assistedFactoryIssue(
                code: "assisted-factory.child-has-no-assisted-input",
                message: "@SubContainerFactory member '\(factory.memberName)' targets '\(child.displayName)', which has no @Input(.assisted) member.",
                factory: factory,
                child: child,
                remediation: "Use @SubContainer for a fixed child, or mark the runtime child input with @Input(.assisted)."
            ))
        }

        var seenChildInputs: Set<String> = []
        for binding in factory.bindings {
            if !seenChildInputs.insert(binding.childInputName).inserted {
                issues.append(ValidationIssue(
                    code: "assisted-factory.duplicate-static-binding",
                    severity: .error,
                    message: "Static child input '\(binding.childInputName)' is bound more than once for @SubContainerFactory member '\(factory.memberName)'.",
                    location: binding.childLocation,
                    remediation: "Keep exactly one binding for each ordinary child @Input."
                ))
                continue
            }
            if child.assistedInputMembers.contains(binding.childInputName) {
                issues.append(ValidationIssue(
                    code: "assisted-factory.assisted-input-bound-as-static",
                    severity: .error,
                    message: "Assisted child input '\(binding.childInputName)' cannot be captured by parent factory member '\(factory.memberName)'.",
                    location: binding.childLocation,
                    remediation: "Remove this binding and pass the value to AssistedFactory.callAsFunction instead."
                ))
            } else if !child.staticInputMembers.contains(binding.childInputName) {
                issues.append(ValidationIssue(
                    code: "assisted-factory.unknown-static-input",
                    severity: .error,
                    message: "Static binding '\(binding.childInputName)' does not name an ordinary @Input on child container '\(child.displayName)'.",
                    location: binding.childLocation,
                    remediation: "Rename the child key path to an ordinary child @Input."
                ))
            }
        }

        let missing = child.staticInputMembers.subtracting(seenChildInputs).sorted()
        if !missing.isEmpty {
            issues.append(assistedFactoryIssue(
                code: "assisted-factory.missing-static-binding",
                message: "@SubContainerFactory member '\(factory.memberName)' is missing static child bindings: \(missing.joined(separator: ", ")).",
                factory: factory,
                child: child,
                remediation: "Add one bindings: tuple for every listed ordinary child @Input."
            ))
        }
    }
    return issues
}

private func assistedFactoryIssue(
    code: String,
    message: String,
    factory: SemanticAssistedFactoryRecord,
    child: SemanticContainerRecord,
    remediation: String
) -> ValidationIssue {
    ValidationIssue(
        code: code,
        severity: .error,
        message: message,
        location: factory.location,
        notes: [
            ValidationIssueNote(
                message: "child container '\(child.path)' is declared here.",
                location: child.location
            )
        ],
        remediation: remediation,
        metadata: [
            "childContainerPath": child.path,
            "parentContainerPath": factory.parentContainerPath,
            "factoryMemberName": factory.memberName,
        ]
    )
}

/// Validates deferred-wrapper spellings independently from sub-container
/// binding rules so either contract can evolve without growing the validator
/// orchestration path.
func validateDeferredWrapperParameters(
    _ parameters: [DeferredWrapperParameterRecord],
    wrapperDeclarationsByPath: [String: WrapperDeclarationRecord],
    wrapperAliasesByPath: [String: WrapperAliasRecord]
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    for parameter in parameters {
        if let aliasKind = resolveWrapperAliasKind(
            for: parameter.headReference.displayPath,
            aliasesByPath: wrapperAliasesByPath
        ) {
            let aliasRecord = wrapperAliasesByPath[
                parameter.headReference.displayPath
            ]
            issues.append(
                ValidationIssue(
                    code: "provide.deferred-wrapper-alias-unsupported",
                    severity: .error,
                    message: "Factory parameter '\(parameter.parameterName)' for '\(parameter.memberName)' uses wrapper alias '\(parameter.headReference.displayPath)'. Wrapper aliases are not supported; spell `InnoDI.\(aliasKind.rawValue)<T>` directly.",
                    location: parameter.location,
                    notes: aliasRecord.map {
                        [
                            ValidationIssueNote(
                                message: "alias '\($0.path)' is declared here.",
                                location: $0.location
                            )
                        ]
                    } ?? [],
                    remediation: "Replace the alias use with `InnoDI.\(aliasKind.rawValue)<...>` in the factory parameter type annotation.",
                    metadata: [
                        "wrapperKind": aliasKind.rawValue,
                        "writtenHead": parameter.headReference.displayPath
                    ]
                )
            )
            continue
        }

        guard let writtenWrapperKind = parameter.writtenWrapperKind else {
            continue
        }

        if canonicalWrapperKind(for: parameter.headReference) != nil {
            continue
        }

        if let exactLocalWrapper = wrapperDeclarationsByPath[
            parameter.headReference.displayPath
        ], exactLocalWrapper.wrapperKind == writtenWrapperKind {
            issues.append(
                ValidationIssue(
                    code: "provide.deferred-wrapper-qualification-required",
                    severity: .error,
                    message: "Factory parameter '\(parameter.parameterName)' for '\(parameter.memberName)' must spell `InnoDI.\(writtenWrapperKind.rawValue)<T>` explicitly. `\(parameter.headReference.displayPath)` resolves to a same-module declaration and is ambiguous for macro expansion.",
                    location: parameter.location,
                    notes: [
                        ValidationIssueNote(
                            message: "same-module declaration '\(exactLocalWrapper.path)' is defined here.",
                            location: exactLocalWrapper.location
                        )
                    ],
                    remediation: "Replace `\(parameter.headReference.displayPath)<...>` with `InnoDI.\(writtenWrapperKind.rawValue)<...>` at the factory parameter site.",
                    metadata: [
                        "wrapperKind": writtenWrapperKind.rawValue,
                        "writtenHead": parameter.headReference.displayPath
                    ]
                )
            )
        }
    }

    return issues
}

private func makeInvalidBindingsIssue(
    for subContainer: SemanticSubContainerRecord,
    location: ValidationIssueLocation
) -> ValidationIssue {
    ValidationIssue(
        code: MacroBuildDiagnosticContract.subInvalidBindingsCode,
        severity: .error,
        message: MacroBuildDiagnosticContract.subInvalidBindingsMessage(
            memberName: subContainer.memberName
        ),
        location: location,
        notes: [],
        remediation: "Use bindings: [(child: \\.childInput, parent: \\.parentMember)] or remove bindings: to use implicit same-name wiring.",
        metadata: [
            "parentContainerPath": subContainer.parentContainerPath,
            "subContainerMemberName": subContainer.memberName
        ]
    )
}
