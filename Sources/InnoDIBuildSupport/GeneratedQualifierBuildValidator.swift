import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftSyntax

/// Target-scoped full-source validation for module qualifiers emitted by
/// `@DIContainer` and `@DIEnvironmentBridge`.
///
/// Compiler macro expansion receives a detached annotated declaration. It can
/// validate the target's direct members and lexical binders, but not sibling
/// files, complete enclosing member lists, matching extensions, or declarations
/// imported from a visible dependency. This pass closes exactly those lookup
/// scopes before source compilation.
package enum GeneratedQualifierBuildValidator {
    package static func validate(
        rootPath: String
    ) throws -> ValidationIssueReport {
        validate(snapshot: try loadWorkspaceSourceSnapshot(rootPath: rootPath))
    }

    package static func validate(
        snapshot: WorkspaceSourceSnapshot
    ) -> ValidationIssueReport {
        let manifest = snapshot.analysisManifest
        let targetIndex = snapshot.analysisTargetIndex
        let moduleNamesByTargetID = Dictionary(
            uniqueKeysWithValues: (manifest?.targets ?? []).map {
                ($0.id, $0.moduleName)
            }
        )
        let scanResults = snapshot.files.map { sourceFile in
            QualifierFileScanResult(
                sourceFile: sourceFile,
                moduleName: sourceFile.targetID.flatMap {
                    moduleNamesByTargetID[$0]
                }
            )
        }
        let primaryTargetID = snapshot.primaryTargetID
        let sites = scanResults
            .flatMap(\.sites)
            .filter { site in
                guard manifest != nil else { return true }
                return site.targetID == primaryTargetID
            }

        var issues = contextIssues(for: sites)
        let supportedSites = sites.filter { $0.context == .supported }
        guard !supportedSites.isEmpty else {
            return ValidationIssueReport(issues: sortedIssues(issues))
        }

        let shadows = scanResults.flatMap(\.shadows)
        let qualifierIndex = QualifierValidationIndex(shadows: shadows)
        let extensions = scanResults.flatMap(\.extensions)
        let nominalDeclarations = scanResults.flatMap(\.nominalDeclarations)
        let typeAliases = scanResults.flatMap(\.typeAliases)
        let nominalTypesByScope = Dictionary(
            grouping: scanResults.flatMap(\.nominalTypes),
            by: { targetScopeKey($0.targetID) }
        )
        let aliasesByScope = Dictionary(
            grouping: scanResults.flatMap(\.typeAliases),
            by: { targetScopeKey($0.targetID) }
        )
        let resolvedExtensionOwners = resolveExtensionOwners(
            extensions: extensions,
            nominalTypesByScope: nominalTypesByScope,
            aliasesByScope: aliasesByScope
        )
        let importsBySourceIdentity = Dictionary(
            uniqueKeysWithValues: scanResults.map {
                ($0.sourceIdentity, $0.imports)
            }
        )
        let exportedImportsByTargetID: [
            WorkspaceTargetID: [QualifierImportEntry]
        ] = scanResults.reduce(into: [:]) { result, scanResult in
            guard let targetID = scanResult.targetID else { return }
            result[targetID, default: []].append(
                contentsOf: scanResult.imports.filter(\.isExported)
            )
        }

        var pending: [PendingQualifierIssueKey: PendingQualifierIssue] = [:]
        var pendingInheritance: [
            PendingInheritanceIssueKey: PendingInheritanceIssue
        ] = [:]
        for site in supportedSites {
            let visibleQualifierNames = qualifierNames(
                requiredBy: site,
                lookupScope: .sameTargetTopLevel
            )
            for shadow in qualifierIndex.shadows(
                targetID: site.targetID,
                names: visibleQualifierNames
            ) {
                guard let lookupScope = lookupScope(
                    of: shadow,
                    from: site,
                    resolvedExtensionOwners: resolvedExtensionOwners
                ), site.isAffected(by: shadow, lookupScope: lookupScope) else {
                    continue
                }
                appendPendingIssue(
                    shadow: shadow,
                    site: site,
                    lookupScope: lookupScope,
                    pending: &pending
                )
            }

            let siteExposures: Set<DependencyExposure>
            if let manifest,
               let siteTargetID = site.targetID {
                siteExposures = dependencyExposures(
                    from: siteTargetID,
                    sourceImports: effectiveImports(
                        for: site.sourceIdentity,
                        targetID: siteTargetID,
                        importsBySourceIdentity: importsBySourceIdentity,
                        exportedImportsByTargetID: exportedImportsByTargetID
                    ),
                    manifest: manifest,
                    targetIndex: targetIndex,
                    exportedImportsByTargetID: exportedImportsByTargetID
                )
                for exposure in siteExposures {
                    guard let dependencyTarget = targetIndex?.target(
                        id: exposure.targetID
                    ),
                          let siteTarget = targetIndex?.target(id: siteTargetID) else {
                        continue
                    }
                    for shadow in qualifierIndex.shadows(
                        targetID: exposure.targetID,
                        names: visibleQualifierNames
                    ) {
                        guard shadow.isVisibleFromDependency(
                                samePackage: dependencyTarget.packageIdentity
                                    == siteTarget.packageIdentity,
                                exposure: exposure
                              ),
                              exposure.exposes(
                                shadow,
                                resolvedExtensionOwners: resolvedExtensionOwners
                              ),
                              site.isAffected(
                                by: shadow,
                                lookupScope: .visibleDependency
                              ) else {
                            continue
                        }
                        appendPendingIssue(
                            shadow: shadow,
                            site: site,
                            lookupScope: .visibleDependency,
                            pending: &pending
                        )
                    }
                }
            } else {
                siteExposures = []
            }

            appendInheritedQualifierIssues(
                for: site,
                nominalDeclarations: nominalDeclarations,
                typeAliases: typeAliases,
                qualifierIndex: qualifierIndex,
                resolvedExtensionOwners: resolvedExtensionOwners,
                manifest: manifest,
                targetIndex: targetIndex,
                importsBySourceIdentity: importsBySourceIdentity,
                exportedImportsByTargetID: exportedImportsByTargetID,
                siteExposures: siteExposures,
                pendingQualifier: &pending,
                pendingInheritance: &pendingInheritance
            )
        }

        issues.append(contentsOf: pending.values.map(\.issue))
        issues.append(contentsOf: pendingInheritance.values.map(\.issue))
        return ValidationIssueReport(issues: sortedIssues(issues))
    }
}

struct QualifierValidationIndex {
    private struct ShadowKey: Hashable {
        let targetScope: String
        let name: String
    }

    private let shadowsByTargetAndName: [
        ShadowKey: [QualifierShadowDeclaration]
    ]

    init(shadows: [QualifierShadowDeclaration]) {
        shadowsByTargetAndName = Dictionary(
            grouping: shadows,
            by: {
                ShadowKey(
                    targetScope: targetScopeKey($0.targetID),
                    name: $0.name
                )
            }
        )
    }

    func shadows(
        targetID: WorkspaceTargetID?,
        names: Set<String>
    ) -> [QualifierShadowDeclaration] {
        let targetScope = targetScopeKey(targetID)
        return names.sorted().flatMap { name in
            shadowsByTargetAndName[
                ShadowKey(targetScope: targetScope, name: name),
                default: []
            ]
        }
    }
}

func qualifierNames(
    requiredBy site: QualifierMacroSite,
    lookupScope: QualifierLookupScope
) -> Set<String> {
    let requirements: Set<GeneratedQualifierRequirement>
    switch lookupScope {
    case .sameTargetTopLevel, .visibleDependency:
        requirements = site.usage.memberBodies.union(
            site.usage.fileScopeExtensions
        )
    case .enclosingNominalMember, .matchingExtensionMember,
         .inheritedSuperclassMember:
        requirements = site.usage.memberBodies
    }
    return Set(requirements.map(\.name))
}

struct PendingQualifierIssueKey: Hashable {
    let code: String
    let shadowID: String
}

struct PendingQualifierIssue {
    let code: String
    let message: String
    let shadow: QualifierShadowDeclaration
    var lookupScopes: Set<String>
    var sitesByIdentity: [String: QualifierMacroSite]

    var issue: ValidationIssue {
        let sites = sitesByIdentity.values.sorted {
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            if $0.location.line != $1.location.line {
                return $0.location.line < $1.location.line
            }
            return $0.location.column < $1.location.column
        }
        return ValidationIssue(
            code: code,
            severity: .error,
            message: message,
            location: shadow.location,
            notes: sites.map { site in
                ValidationIssueNote(
                    message: "affected \(site.kind.rawValue) target '\(site.targetPath ?? site.declarationName)' is declared here.",
                    location: site.location
                )
            },
            remediation: "Rename '\(shadow.name)' so generated module-qualified references remain unambiguous.",
            metadata: [
                "affectedSiteCount": String(sites.count),
                "lookupScopes": lookupScopes.sorted().joined(separator: ","),
                "qualifier": shadow.name,
            ]
        )
    }
}

func appendPendingIssue(
    shadow: QualifierShadowDeclaration,
    site: QualifierMacroSite,
    lookupScope: QualifierLookupScope,
    pending: inout [PendingQualifierIssueKey: PendingQualifierIssue]
) {
    let code: String
    let message: String
    switch site.kind {
    case .container:
        code = GeneratedQualifierDiagnosticContract
            .containerReservedModuleNameCode
        message = GeneratedQualifierDiagnosticContract
            .containerReservedModuleNameMessage(
                declarationName: shadow.name
            )
    case .environmentBridge:
        code = GeneratedQualifierDiagnosticContract
            .environmentBridgeReservedModuleNameCode
        message = GeneratedQualifierDiagnosticContract
            .environmentBridgeReservedModuleNameMessage(
                declarationName: shadow.name
            )
    }
    let key = PendingQualifierIssueKey(code: code, shadowID: shadow.id)
    let siteIdentity = "\(site.sourceIdentity)#\(site.location.line):\(site.location.column)#\(site.kind.rawValue)"
    if var existing = pending[key] {
        existing.lookupScopes.insert(lookupScope.rawValue)
        existing.sitesByIdentity[siteIdentity] = site
        pending[key] = existing
    } else {
        pending[key] = PendingQualifierIssue(
            code: code,
            message: message,
            shadow: shadow,
            lookupScopes: [lookupScope.rawValue],
            sitesByIdentity: [siteIdentity: site]
        )
    }
}

private func lookupScope(
    of shadow: QualifierShadowDeclaration,
    from site: QualifierMacroSite,
    resolvedExtensionOwners: [String: String]
) -> QualifierLookupScope? {
    if let declaredPath = shadow.declaredPath?.joined(separator: "."),
       site.macroCoveredDeclarationPaths.contains(declaredPath) {
        return nil
    }
    switch shadow.scope {
    case .file:
        guard shadow.access != .private && shadow.access != .fileprivate
                || shadow.sourceIdentity == site.sourceIdentity else {
            return nil
        }
        return .sameTargetTopLevel
    case .nominal(let path):
        guard site.lookupOwnerPaths.contains(path),
              path != site.targetPath else {
            // Direct target members remain owned by the attached macro.
            return nil
        }
        return .enclosingNominalMember
    case .extension(let id):
        guard let owner = resolvedExtensionOwners[id],
              site.lookupOwnerPaths.contains(owner),
              shadow.access != .private && shadow.access != .fileprivate
                || shadow.sourceIdentity == site.sourceIdentity else {
            return nil
        }
        return .matchingExtensionMember
    case .local:
        return nil
    }
}

private func resolveExtensionOwners(
    extensions: [QualifierExtensionScope],
    nominalTypesByScope: [String: [TargetScopedNominalType]],
    aliasesByScope: [String: [TargetScopedTypeAlias]]
) -> [String: String] {
    var result: [String: String] = [:]
    for extensionScope in extensions {
        let key = targetScopeKey(extensionScope.targetID)
        let nominalTypes = nominalTypesByScope[key, default: []].map(\.record)
        let aliases = aliasesByScope[key, default: []].map(\.record)
        let resolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: aliases
        )
        let resolution = resolver.resolvePath(
            for: extensionScope.reference,
            candidatePaths: Set(nominalTypes.map(\.path))
        )
        if resolution.state == .resolved,
           let path = resolution.resolvedPath {
            result[extensionScope.id] = path
            continue
        }
        guard resolution.state == .unresolved else {
            continue
        }

        // Preserve an exact nested-type interpretation first. Only after it
        // fails do we strip a known self-module prefix from the extension and
        // alias targets. Root-path mode has no module identity, so the same
        // suffix attempt is deliberately conservative.
        let fallbackReference = droppingQualifierModulePrefix(
            from: extensionScope.reference,
            moduleName: extensionScope.moduleName,
            importedModuleNames: extensionScope.importedModuleNames
        ) ?? extensionScope.reference
        let fallbackAliases = aliases.map { alias in
            SemanticTypeAliasRecord(
                path: alias.path,
                components: alias.components,
                target: droppingQualifierModulePrefix(
                    from: alias.target,
                    moduleName: extensionScope.moduleName,
                    importedModuleNames: extensionScope.importedModuleNames
                ) ?? alias.target
            )
        }
        guard fallbackReference != extensionScope.reference
                || fallbackAliases != aliases else {
            continue
        }
        let fallbackResolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: fallbackAliases
        )
        let fallback = fallbackResolver.resolvePath(
            for: fallbackReference,
            candidatePaths: Set(nominalTypes.map(\.path))
        )
        if fallback.state == .resolved,
           let path = fallback.resolvedPath {
            result[extensionScope.id] = path
        }
    }
    return result
}

func droppingQualifierModulePrefix(
    from reference: SemanticTypeReference,
    moduleName: String?,
    importedModuleNames: Set<String> = []
) -> SemanticTypeReference? {
    guard reference.components.count > 1 else {
        return nil
    }
    if let moduleName,
       reference.components.first != moduleName {
        return nil
    }
    if moduleName == nil,
       let first = reference.components.first,
       importedModuleNames.contains(first) {
        return nil
    }
    let components = Array(reference.components.dropFirst())
    return SemanticTypeReference(
        displayPath: components.joined(separator: "."),
        components: components
    )
}

func effectiveImports(
    for sourceIdentity: String,
    targetID: WorkspaceTargetID,
    importsBySourceIdentity: [String: [QualifierImportEntry]],
    exportedImportsByTargetID: [
        WorkspaceTargetID: [QualifierImportEntry]
    ]
) -> [QualifierImportEntry] {
    // Exported imports contribute their public/package surface to sibling
    // files, but source-local @testable and @_spi capabilities do not cross
    // that file boundary.
    let moduleWideExports = exportedImportsByTargetID[
        targetID,
        default: []
    ].map { entry in
        QualifierImportEntry(
            moduleName: entry.moduleName,
            declarationPath: entry.declarationPath,
            isExported: true,
            isTestable: false,
            spiGroups: []
        )
    }
    return (importsBySourceIdentity[sourceIdentity] ?? [])
        + moduleWideExports
}

func dependencyExposures(
    from siteTargetID: WorkspaceTargetID,
    sourceImports: [QualifierImportEntry],
    manifest: WorkspaceAnalysisManifest,
    targetIndex: WorkspaceAnalysisTargetIndex?,
    exportedImportsByTargetID: [WorkspaceTargetID: [QualifierImportEntry]]
) -> Set<DependencyExposure> {
    guard let siteTarget = targetIndex?.target(id: siteTargetID) else {
        return []
    }
    let targetsByModuleName = Dictionary(
        grouping: manifest.targets,
        by: \.moduleName
    )
    var exposures: Set<DependencyExposure> = []
    var pending: [DependencyExposure] = []

    func appendImports(
        _ imports: [QualifierImportEntry],
        from target: WorkspaceAnalysisTarget,
        propagatedVisibility: (
            isTestable: Bool,
            spiGroups: Set<String>
        )? = nil
    ) {
        let directDependencies = Set(target.directDependencyTargetIDs)
        for entry in imports {
            for dependency in targetsByModuleName[entry.moduleName, default: []]
                where directDependencies.contains(dependency.id) {
                let exposure = DependencyExposure(
                    targetID: dependency.id,
                    declarationPath: entry.declarationPath,
                    isTestable: propagatedVisibility?.isTestable
                        ?? entry.isTestable,
                    spiGroups: propagatedVisibility?.spiGroups
                        ?? entry.spiGroups
                )
                if exposures.insert(exposure).inserted {
                    pending.append(exposure)
                }
            }
        }
    }

    appendImports(sourceImports, from: siteTarget)
    while let exposure = pending.popLast() {
        // Selective imports do not inherit a dependency module's re-exports.
        guard exposure.declarationPath == nil,
              let dependencyTarget = targetIndex?.target(id: exposure.targetID) else {
            continue
        }
        appendImports(
            exportedImportsByTargetID[exposure.targetID, default: []],
            from: dependencyTarget,
            // A client's SPI capability flows through a re-export chain;
            // @testable access never does. Attributes written on the
            // intermediate export govern that source file, not its clients.
            propagatedVisibility: (
                isTestable: false,
                spiGroups: exposure.spiGroups
            )
        )
    }
    return exposures
}

private func contextIssues(
    for sites: [QualifierMacroSite]
) -> [ValidationIssue] {
    sites.compactMap { site in
        guard site.kind == .environmentBridge else { return nil }
        switch site.context {
        case .supported:
            return nil
        case .extensionContext:
            return ValidationIssue(
                code: GeneratedQualifierDiagnosticContract
                    .environmentBridgeExtensionContextUnsupportedCode,
                severity: .error,
                message: GeneratedQualifierDiagnosticContract
                    .environmentBridgeExtensionContextUnsupportedMessage,
                location: site.location,
                remediation: "Move the bridge target out of the extension lookup context and declare it at file or nominal scope.",
                metadata: ["bridgeTarget": site.declarationName]
            )
        case .local(let context):
            return ValidationIssue(
                code: GeneratedQualifierDiagnosticContract
                    .environmentBridgeLocalDeclarationUnsupportedCode,
                severity: .error,
                message: GeneratedQualifierDiagnosticContract
                    .environmentBridgeLocalDeclarationUnsupportedMessage(
                        declarationName: site.declarationName,
                        context: context
                    ),
                location: site.location,
                remediation: "Move the bridge target out of executable code and declare it at file or nominal scope.",
                metadata: [
                    "bridgeTarget": site.declarationName,
                    "localContext": context,
                ]
            )
        }
    }
}

func targetScopeKey(_ targetID: WorkspaceTargetID?) -> String {
    targetID?.rawValue ?? "<root-path-workspace>"
}

private func sortedIssues(_ issues: [ValidationIssue]) -> [ValidationIssue] {
    issues.sorted {
        if $0.location.filePath != $1.location.filePath {
            return $0.location.filePath < $1.location.filePath
        }
        if $0.location.line != $1.location.line {
            return $0.location.line < $1.location.line
        }
        if $0.location.column != $1.location.column {
            return $0.location.column < $1.location.column
        }
        return $0.code < $1.code
    }
}
