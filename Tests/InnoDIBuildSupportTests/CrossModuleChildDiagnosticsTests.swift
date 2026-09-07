import Foundation
import InnoDICore
import Testing

@testable import InnoDIBuildSupport

@Suite("Cross-module child diagnostics")
struct CrossModuleChildDiagnosticsTests {

    private func makeEdge(
        parentModule: ResolvedHierarchyModuleContext? = nil,
        childModule: ResolvedHierarchyModuleContext? = nil
    ) -> ResolvedHierarchyEdge {
        ResolvedHierarchyEdge(
            parentContainerID: "AppContainer#1",
            parentPath: "AppContainer",
            parentLocation: ValidationIssueLocation(filePath: "App.swift", line: 1, column: 1),
            parentModule: parentModule,
            subContainer: WorkspaceHierarchySubContainerRecord(
                memberName: "feature",
                location: ValidationIssueLocation(filePath: "App.swift", line: 4, column: 5),
                childReferenceDisplayPath: "FeatureContainer",
                childReference: nil,
                sameNameWiring: .omitted,
                bindings: [],
                hasBindingsArgument: false,
                invalidBindingsLocation: nil
            ),
            childContainerID: "FeatureContainer#missing",
            childPath: "FeatureContainer",
            childLocation: ValidationIssueLocation(filePath: "App.swift", line: 4, column: 23),
            childModule: childModule
        )
    }

    @Test("Child not in workspace produces an actionable warning, not a silent skip")
    func missingChildEmitsWarningInsteadOfSilentSkip() {
        let edge = makeEdge()
        let issue = makeChildContainerOutOfWorkspaceIssue(edge: edge)

        #expect(issue.code == "hierarchy.child-not-in-workspace")
        #expect(issue.severity == .warning)
        #expect(issue.location.filePath == "App.swift")
        #expect(issue.location.line == 4)
        #expect(issue.metadata["parentContainerPath"] == "AppContainer")
        #expect(issue.metadata["childContainerPath"] == "FeatureContainer")
        #expect(issue.metadata["childContainerID"] == "FeatureContainer#missing")
        #expect(issue.message.contains("workspace validator could not find a container record"))
        // Remediation must reference both component opt-in and module dependency declaration.
        #expect(issue.remediation?.contains("ContainerRole.component") == true)
        #expect(issue.remediation?.contains("module") == true)
    }

    @Test("Child module presence enriches the diagnostic without changing the code")
    func childModuleEnrichesNotesAndMetadata() {
        // Manufacture module contexts via a synthetic record helper. The test only
        // needs the displayName/manifestPath fields to flow into the notes and
        // metadata; moduleID drives the metadata key.
        let parentRecord = WorkspaceModuleRecord(
            moduleID: "Parent",
            name: "AppFeature",
            manifestPath: "/tmp/Package.swift",
            packageDisplayName: nil,
            packageIdentity: nil,
            sourcePatterns: [],
            dependencyRefs: [],
            swiftPMPackageDependencies: [],
            buildSystem: "swiftpm"
        )
        let childRecord = WorkspaceModuleRecord(
            moduleID: "Child",
            name: "FeatureModule",
            manifestPath: "/tmp/ChildPackage.swift",
            packageDisplayName: nil,
            packageIdentity: nil,
            sourcePatterns: [],
            dependencyRefs: [],
            swiftPMPackageDependencies: [],
            buildSystem: "swiftpm"
        )

        let edge = makeEdge(
            parentModule: ResolvedHierarchyModuleContext(record: parentRecord),
            childModule: ResolvedHierarchyModuleContext(record: childRecord)
        )

        let issue = makeChildContainerOutOfWorkspaceIssue(edge: edge)

        #expect(issue.code == "hierarchy.child-not-in-workspace")
        #expect(issue.severity == .warning)
        #expect(issue.metadata["parentModule"] == "AppFeature")
        #expect(issue.metadata["parentModuleID"] == "Parent")
        #expect(issue.metadata["parentManifestPath"] == "/tmp/Package.swift")
        #expect(issue.metadata["childModule"] == "FeatureModule")
        #expect(issue.metadata["childModuleID"] == "Child")
        #expect(issue.metadata["childManifestPath"] == "/tmp/ChildPackage.swift")
        // The note set must include the workspace-not-loaded explanation.
        #expect(issue.notes.contains { $0.message.contains("not visible to this validation pass") })
        #expect(issue.notes.contains { $0.message.contains("declares a dependency on the child target/product") })
        #expect(issue.remediation?.contains("child target/product") == true)
    }

    @Test("validateResolvedEdges surfaces the warning instead of skipping silently")
    func validatorEmitsWarningWhenChildAbsentFromContainersByID() {
        let edge = makeEdge()
        let containersByID: [String: WorkspaceHierarchyContainerRecord] = [:]
        let moduleGraph = WorkspaceModuleGraphSnapshot(modules: [], swiftPMProducts: [])
        let resolver = SemanticResolverIndex(nominalTypes: [], topLevelTypeAliases: [])

        let issues = validateResolvedEdges(
            [edge],
            containersByID: containersByID,
            moduleGraph: moduleGraph,
            resolver: resolver,
            typeCandidatePaths: []
        )

        #expect(issues.count == 1)
        #expect(issues.first?.code == "hierarchy.child-not-in-workspace")
        #expect(issues.first?.severity == .warning)
    }
}
