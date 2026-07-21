import InnoDICore
import InnoDIWorkspaceAnalysis

// Resolves superclass chains and validates inherited generated-qualifier
// shadowing independently from direct lexical and dependency lookups.
struct PendingInheritanceIssueKey: Hashable {
    let classID: String
    let resolutionState: SemanticResolutionState
}

struct PendingInheritanceIssue {
    let declaration: QualifierNominalDeclaration
    let inheritance: QualifierInheritanceReference
    let resolutionState: SemanticResolutionState
    var sitesByIdentity: [String: QualifierMacroSite]

    var issue: ValidationIssue {
        let sites = sitesByIdentity.values.sorted(by: qualifierSiteSortOrder)
        return ValidationIssue(
            code: GeneratedQualifierDiagnosticContract
                .inheritanceUnverifiableCode,
            severity: .error,
            message: GeneratedQualifierDiagnosticContract
                .inheritanceUnverifiableMessage(
                    className: declaration.path,
                    inheritedType: inheritance.reference.displayPath,
                    resolutionState: resolutionState.rawValue
                ),
            location: inheritance.location,
            notes: sites.map { site in
                ValidationIssueNote(
                    message: "affected \(site.kind.rawValue) target '\(site.targetPath ?? site.declarationName)' is declared here.",
                    location: site.location
                )
            },
            remediation: "Make the superclass or protocol declaration and any typealias chain source-visible to InnoDI's target-scoped build preflight.",
            metadata: [
                "affectedSiteCount": String(sites.count),
                "class": declaration.path,
                "inheritedType": inheritance.reference.displayPath,
                "resolutionState": resolutionState.rawValue,
            ]
        )
    }
}

private func qualifierSiteSortOrder(
    _ lhs: QualifierMacroSite,
    _ rhs: QualifierMacroSite
) -> Bool {
    if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
    if lhs.location.line != rhs.location.line {
        return lhs.location.line < rhs.location.line
    }
    return lhs.location.column < rhs.location.column
}

private struct VisibleInheritanceNominal {
    let resolutionPath: String
    let declaration: QualifierNominalDeclaration
}

private struct VisibleInheritanceAlias {
    let record: SemanticTypeAliasRecord
    let isSameTarget: Bool
}

private enum InheritanceTargetResolution {
    case resolved(QualifierNominalDeclaration)
    case unverifiable(SemanticResolutionState)
}

func appendInheritedQualifierIssues(
    for site: QualifierMacroSite,
    nominalDeclarations: [QualifierNominalDeclaration],
    typeAliases: [TargetScopedTypeAlias],
    qualifierIndex: QualifierValidationIndex,
    resolvedExtensionOwners: [String: String],
    manifest: WorkspaceAnalysisManifest?,
    importsBySourceIdentity: [String: [QualifierImportEntry]],
    exportedImportsByTargetID: [
        WorkspaceTargetID: [QualifierImportEntry]
    ],
    siteExposures: Set<DependencyExposure>,
    pendingQualifier: inout [
        PendingQualifierIssueKey: PendingQualifierIssue
    ],
    pendingInheritance: inout [
        PendingInheritanceIssueKey: PendingInheritanceIssue
    ]
) {
    guard site.hasInheritedQualifierRequirements else {
        return
    }
    let inheritedQualifierNames = qualifierNames(
        requiredBy: site,
        lookupScope: .inheritedSuperclassMember
    )

    let startingClasses = nominalDeclarations
        .filter { declaration in
            declaration.kind == .class
                && targetScopeKey(declaration.targetID)
                    == targetScopeKey(site.targetID)
                && site.lookupOwnerPaths.contains(declaration.path)
        }
        .sorted { lhs, rhs in
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.id < rhs.id
        }

    for startingClass in startingClasses {
        var currentClass = startingClass
        var visitedClassIDs: Set<String> = []

        inheritanceChain: while visitedClassIDs.insert(currentClass.id).inserted {
            guard let inheritance = currentClass.firstInheritance else {
                break
            }
            let resolution = resolveFirstInheritance(
                of: currentClass,
                inheritance: inheritance,
                nominalDeclarations: nominalDeclarations,
                typeAliases: typeAliases,
                manifest: manifest,
                importsBySourceIdentity: importsBySourceIdentity,
                exportedImportsByTargetID: exportedImportsByTargetID
            )
            switch resolution {
            case .unverifiable(let state):
                appendPendingInheritanceIssue(
                    declaration: currentClass,
                    inheritance: inheritance,
                    resolutionState: state,
                    site: site,
                    pending: &pendingInheritance
                )
                break inheritanceChain
            case .resolved(let inheritedDeclaration):
                guard inheritedDeclaration.kind == .class else {
                    // A source-visible first protocol means there is no
                    // superclass chain to inspect.
                    break inheritanceChain
                }
                for shadow in qualifierIndex.shadows(
                    targetID: inheritedDeclaration.targetID,
                    names: inheritedQualifierNames
                ) {
                    guard isInheritedMember(
                            shadow,
                            of: inheritedDeclaration,
                            resolvedExtensionOwners: resolvedExtensionOwners
                          ),
                          isInheritedShadowVisible(
                            shadow,
                            from: site,
                            manifest: manifest,
                            siteExposures: siteExposures
                          ),
                          site.isAffected(
                            by: shadow,
                            lookupScope: .inheritedSuperclassMember
                          ) else {
                        continue
                    }
                    appendPendingIssue(
                        shadow: shadow,
                        site: site,
                        lookupScope: .inheritedSuperclassMember,
                        pending: &pendingQualifier
                    )
                }
                currentClass = inheritedDeclaration
            }
        }
    }
}

private func appendPendingInheritanceIssue(
    declaration: QualifierNominalDeclaration,
    inheritance: QualifierInheritanceReference,
    resolutionState: SemanticResolutionState,
    site: QualifierMacroSite,
    pending: inout [
        PendingInheritanceIssueKey: PendingInheritanceIssue
    ]
) {
    let key = PendingInheritanceIssueKey(
        classID: declaration.id,
        resolutionState: resolutionState
    )
    let siteIdentity = "\(site.sourceIdentity)#\(site.location.line):\(site.location.column)#\(site.kind.rawValue)"
    if var existing = pending[key] {
        existing.sitesByIdentity[siteIdentity] = site
        pending[key] = existing
    } else {
        pending[key] = PendingInheritanceIssue(
            declaration: declaration,
            inheritance: inheritance,
            resolutionState: resolutionState,
            sitesByIdentity: [siteIdentity: site]
        )
    }
}

private func resolveFirstInheritance(
    of declaration: QualifierNominalDeclaration,
    inheritance: QualifierInheritanceReference,
    nominalDeclarations: [QualifierNominalDeclaration],
    typeAliases: [TargetScopedTypeAlias],
    manifest: WorkspaceAnalysisManifest?,
    importsBySourceIdentity: [String: [QualifierImportEntry]],
    exportedImportsByTargetID: [
        WorkspaceTargetID: [QualifierImportEntry]
    ]
) -> InheritanceTargetResolution {
    let exposures: Set<DependencyExposure>
    if let manifest,
       let targetID = declaration.targetID {
        exposures = dependencyExposures(
            from: targetID,
            sourceImports: effectiveImports(
                for: declaration.sourceIdentity,
                targetID: targetID,
                importsBySourceIdentity: importsBySourceIdentity,
                exportedImportsByTargetID: exportedImportsByTargetID
            ),
            manifest: manifest,
            exportedImportsByTargetID: exportedImportsByTargetID
        )
    } else {
        exposures = []
    }

    let visibleNominals = visibleInheritanceNominals(
        from: declaration,
        declarations: nominalDeclarations,
        exposures: exposures,
        manifest: manifest
    )
    let visibleAliases = visibleInheritanceAliases(
        from: declaration,
        aliases: typeAliases,
        exposures: exposures,
        manifest: manifest
    )
    let declarationsByResolutionPath = Dictionary(
        grouping: visibleNominals,
        by: \.resolutionPath
    )
    let nominalRecords = declarationsByResolutionPath.keys.sorted().map {
        path in
        SemanticNominalTypeRecord(
            path: path,
            components: path.split(separator: ".").map(String.init)
        )
    }

    func mappedResolution(
        reference: SemanticTypeReference,
        aliases: [SemanticTypeAliasRecord]
    ) -> InheritanceTargetResolution {
        let result = SemanticResolverIndex(
            nominalTypes: nominalRecords,
            topLevelTypeAliases: aliases
        ).resolvePath(
            for: reference,
            candidatePaths: Set(declarationsByResolutionPath.keys)
        )
        guard result.state == .resolved,
              let path = result.resolvedPath else {
            let state = result.state == .excluded
                ? SemanticResolutionState.unresolved
                : result.state
            return .unverifiable(state)
        }
        let declarations = Dictionary(
            uniqueKeysWithValues: declarationsByResolutionPath[
                path,
                default: []
            ].map { ($0.declaration.id, $0.declaration) }
        ).values
        guard declarations.count == 1,
              let resolved = declarations.first else {
            return .unverifiable(.ambiguous)
        }
        return .resolved(resolved)
    }

    let rawAliases = visibleAliases.map(\.record)
    let rawResolution = mappedResolution(
        reference: inheritance.reference,
        aliases: rawAliases
    )
    if case .unverifiable(.unresolved) = rawResolution {
        let fallbackReference = droppingQualifierModulePrefix(
            from: inheritance.reference,
            moduleName: declaration.moduleName
        ) ?? inheritance.reference
        let fallbackAliases = visibleAliases.map { alias in
            guard alias.isSameTarget else { return alias.record }
            return SemanticTypeAliasRecord(
                path: alias.record.path,
                components: alias.record.components,
                target: droppingQualifierModulePrefix(
                    from: alias.record.target,
                    moduleName: declaration.moduleName
                ) ?? alias.record.target
            )
        }
        if fallbackReference != inheritance.reference
            || fallbackAliases != rawAliases {
            return mappedResolution(
                reference: fallbackReference,
                aliases: fallbackAliases
            )
        }
    }
    return rawResolution
}

private func visibleInheritanceNominals(
    from declaration: QualifierNominalDeclaration,
    declarations: [QualifierNominalDeclaration],
    exposures: Set<DependencyExposure>,
    manifest: WorkspaceAnalysisManifest?
) -> [VisibleInheritanceNominal] {
    var result: [VisibleInheritanceNominal] = []
    for candidate in declarations {
        if targetScopeKey(candidate.targetID)
            == targetScopeKey(declaration.targetID) {
            guard isSameTargetDeclarationVisible(
                access: candidate.access,
                sourceIdentity: candidate.sourceIdentity,
                fromSourceIdentity: declaration.sourceIdentity
            ) else {
                continue
            }
            result.append(
                VisibleInheritanceNominal(
                    resolutionPath: candidate.path,
                    declaration: candidate
                )
            )
            continue
        }

        guard let manifest,
              let candidateTargetID = candidate.targetID,
              let declarationTargetID = declaration.targetID,
              let candidateTarget = manifest.target(id: candidateTargetID),
              let declarationTarget = manifest.target(id: declarationTargetID),
              exposures.contains(where: { exposure in
                  exposure.targetID == candidateTargetID
                      && dependencyExposure(
                        exposure,
                        exposesPath: candidate.path,
                        scope: candidate.scope
                      )
                      && isDependencyDeclarationVisible(
                        access: candidate.access,
                        spiGroups: candidate.spiGroups,
                        samePackage: candidateTarget.packageIdentity
                            == declarationTarget.packageIdentity,
                        exposure: exposure
                      )
              }) else {
            continue
        }
        let moduleName = candidate.moduleName ?? candidateTarget.moduleName
        result.append(
            VisibleInheritanceNominal(
                resolutionPath: "\(moduleName).\(candidate.path)",
                declaration: candidate
            )
        )
    }
    return result
}

private func visibleInheritanceAliases(
    from declaration: QualifierNominalDeclaration,
    aliases: [TargetScopedTypeAlias],
    exposures: Set<DependencyExposure>,
    manifest: WorkspaceAnalysisManifest?
) -> [VisibleInheritanceAlias] {
    var result: [VisibleInheritanceAlias] = []
    for alias in aliases {
        if targetScopeKey(alias.targetID)
            == targetScopeKey(declaration.targetID) {
            guard isSameTargetDeclarationVisible(
                access: alias.access,
                sourceIdentity: alias.sourceIdentity,
                fromSourceIdentity: declaration.sourceIdentity
            ) else {
                continue
            }
            result.append(
                VisibleInheritanceAlias(
                    record: alias.record,
                    isSameTarget: true
                )
            )
            continue
        }

        guard let manifest,
              let candidateTargetID = alias.targetID,
              let declarationTargetID = declaration.targetID,
              let candidateTarget = manifest.target(id: candidateTargetID),
              let declarationTarget = manifest.target(id: declarationTargetID),
              exposures.contains(where: { exposure in
                  exposure.targetID == candidateTargetID
                      && dependencyExposure(
                        exposure,
                        exposesPath: alias.record.path,
                        scope: alias.scope
                      )
                      && isDependencyDeclarationVisible(
                        access: alias.access,
                        spiGroups: alias.spiGroups,
                        samePackage: candidateTarget.packageIdentity
                            == declarationTarget.packageIdentity,
                        exposure: exposure
                      )
              }) else {
            continue
        }
        let moduleName = alias.moduleName ?? candidateTarget.moduleName
        let components = [moduleName] + alias.record.components
        result.append(
            VisibleInheritanceAlias(
                record: SemanticTypeAliasRecord(
                    path: components.joined(separator: "."),
                    components: components,
                    target: alias.record.target
                ),
                isSameTarget: false
            )
        )
    }
    return result
}

private func isSameTargetDeclarationVisible(
    access: QualifierDeclarationAccess,
    sourceIdentity: String,
    fromSourceIdentity: String
) -> Bool {
    switch access {
    case .private, .fileprivate:
        return sourceIdentity == fromSourceIdentity
    case .internal, .package, .public:
        return true
    }
}

private func isDependencyDeclarationVisible(
    access: QualifierDeclarationAccess,
    spiGroups: Set<String>,
    samePackage: Bool,
    exposure: DependencyExposure
) -> Bool {
    guard spiGroups.isEmpty
            || !spiGroups.isDisjoint(with: exposure.spiGroups) else {
        return false
    }
    switch access {
    case .public:
        return true
    case .package:
        return samePackage
    case .internal:
        return exposure.isTestable
    case .private, .fileprivate:
        return false
    }
}

private func dependencyExposure(
    _ exposure: DependencyExposure,
    exposesPath path: String,
    scope: QualifierShadowScope
) -> Bool {
    switch scope {
    case .file, .nominal:
        break
    case .extension, .local:
        return false
    }
    let components = path.split(separator: ".").map(String.init)
    guard let declarationPath = exposure.declarationPath else {
        return !components.isEmpty
    }
    if components == declarationPath {
        return true
    }
    guard components.count > declarationPath.count else {
        return false
    }
    return Array(components.prefix(declarationPath.count)) == declarationPath
}

private func isInheritedMember(
    _ shadow: QualifierShadowDeclaration,
    of declaration: QualifierNominalDeclaration,
    resolvedExtensionOwners: [String: String]
) -> Bool {
    switch shadow.scope {
    case .nominal(let path):
        return path == declaration.path
    case .extension(let id):
        return resolvedExtensionOwners[id] == declaration.path
    case .file, .local:
        return false
    }
}

private func isInheritedShadowVisible(
    _ shadow: QualifierShadowDeclaration,
    from site: QualifierMacroSite,
    manifest: WorkspaceAnalysisManifest?,
    siteExposures: Set<DependencyExposure>
) -> Bool {
    if targetScopeKey(shadow.targetID) == targetScopeKey(site.targetID) {
        switch shadow.access {
        case .private:
            return false
        case .fileprivate:
            return shadow.sourceIdentity == site.sourceIdentity
        case .internal, .package, .public:
            return true
        }
    }

    guard let manifest,
          let shadowTargetID = shadow.targetID,
          let siteTargetID = site.targetID,
          let shadowTarget = manifest.target(id: shadowTargetID),
          let siteTarget = manifest.target(id: siteTargetID) else {
        return false
    }
    let matchingExposures = siteExposures.filter {
        $0.targetID == shadowTargetID
    }
    guard shadow.spiGroups.isEmpty
            || matchingExposures.contains(where: {
                !shadow.spiGroups.isDisjoint(with: $0.spiGroups)
            }) else {
        return false
    }
    switch shadow.access {
    case .public:
        return true
    case .package:
        return shadowTarget.packageIdentity == siteTarget.packageIdentity
    case .internal:
        return matchingExposures.contains(where: \.isTestable)
    case .private, .fileprivate:
        return false
    }
}
