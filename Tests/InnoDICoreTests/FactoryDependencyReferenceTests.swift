import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

@Suite("Factory dependency semantic records")
struct FactoryDependencyReferenceTests {
    @Test("Typed parameters preserve names, edge kinds, and nominal targets")
    func typedParameters() throws {
        let expression = try factoryExpression(
            """
            { (
                service: Service,
                child: InnoDI.Lazy<Feature.Container>,
                makeOther provider: Provider<OtherContainer>,
                _: Provider<IgnoredContainer>
            ) in service }
            """
        )

        let references = try #require(
            managedFactoryDependencyReferences(in: expression)
        )

        #expect(references == [
            FactoryDependencyReference(
                name: "service",
                kind: .hard,
                targetReference: SemanticTypeReference(
                    displayPath: "Service",
                    components: ["Service"]
                )
            ),
            FactoryDependencyReference(
                name: "child",
                kind: .lazy,
                targetReference: SemanticTypeReference(
                    displayPath: "Feature.Container",
                    components: ["Feature", "Container"]
                )
            ),
            FactoryDependencyReference(
                name: "provider",
                kind: .provider,
                targetReference: SemanticTypeReference(
                    displayPath: "OtherContainer",
                    components: ["OtherContainer"]
                )
            ),
        ])
    }

    @Test("Simple parameters are hard dependencies without type claims")
    func simpleParameters() throws {
        let expression = try factoryExpression(
            "{ first, _, second in first }"
        )

        #expect(managedFactoryDependencyReferences(in: expression) == [
            FactoryDependencyReference(
                name: "first",
                kind: .hard,
                targetReference: nil
            ),
            FactoryDependencyReference(
                name: "second",
                kind: .hard,
                targetReference: nil
            ),
        ])
    }

    @Test("Closure and non-closure inputs remain distinguishable")
    func closureBoundary() throws {
        let noParameters = try factoryExpression("{ Service() }")
        let nonClosure = try factoryExpression("Service()")

        #expect(managedFactoryDependencyReferences(in: noParameters) == [])
        #expect(managedFactoryDependencyReferences(in: nonClosure) == nil)
    }
}

private func factoryExpression(_ source: String) throws -> ExprSyntax {
    let file = Parser.parse(
        source: """
        struct Container {
            @Provide(factory: \(source)) var value: Service
        }
        """
    )
    let declaration = try #require(
        file.statements.first?.item.as(StructDeclSyntax.self)
    )
    let variable = try #require(
        declaration.memberBlock.members.first?.decl.as(
            VariableDeclSyntax.self
        )
    )
    let attribute = try #require(
        findInnoDIAttribute(named: "Provide", in: variable.attributes)
    )
    return try #require(parseProvideArguments(attribute).factoryExpr)
}
