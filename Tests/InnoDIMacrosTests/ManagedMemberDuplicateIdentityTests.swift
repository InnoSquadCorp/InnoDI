import InnoDICore
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("Managed member duplicate identity")
struct ManagedMemberDuplicateIdentityTests {
    private static let roles = [
        "@Input", "@InnoDI.Input", "@Input(.assisted)",
        "@Provide(.shared, factory: 1)", "@InnoDI.Provide(.input)",
        "@SubContainerFactory(Child.self)", "@Multibinding(.shared, factory: 1)",
        "@SubContainer(scope: .shared)", "@InnoDI.SubContainer(scope: .transient)",
    ]

    @Test("All supported managed roles share duplicate identity for ordinary and Unicode names")
    func supportedRolesShareIdentity() throws {
        for left in Self.roles {
            for right in Self.roles {
                for name in ["service", "서비스", "café"] {
                    for mainActor in [false, true] {
                        let container = try parse("\(left) var \(name): Int\n\(right) var \(name): Int")
                        for member in variables(in: container) {
                            #expect(hasDuplicateManagedMemberName(member, in: container, options: options(mainActor)))
                        }
                        let distinct = try parse("\(left) var \(name): Int\n\(right) var unrelated: Int")
                        for member in variables(in: distinct) {
                            #expect(!hasDuplicateManagedMemberName(member, in: distinct, options: options(mainActor)))
                        }
                    }
                }
            }
        }
    }

    @Test("Unsupported same-name siblings cannot suppress a valid member's generated storage")
    func unsupportedSameNameSiblingsDoNotCompete() throws {
        let unsupported = [
            "var NAME: Int", "@Input let NAME: Int", "@Input static var NAME: Int",
            "@Input class var NAME: Int", "@Input lazy var NAME: Int", "@Input weak var NAME: AnyObject?",
            "@Input unowned var NAME: AnyObject", "@Input private(set) var NAME: Int",
            "@Input var NAME: Int { 1 }", "@Input var NAME: Int { get { 1 } }",
            "@Input var NAME: Int { didSet {} }", "@Input var NAME: Int, second: Int",
            "@Input var (NAME, second): (Int, Int)", "@Input var NAME = 1",
            "@Input @Input var NAME: Int", "@Input @Provide(.input) var NAME: Int",
            "@Input @SubContainer var NAME: Int", "@SubContainer @SubContainer var NAME: Int",
            "@Input @Wrapper var NAME: Int", "@Input @MainActor var NAME: Int",
            "@Input @OtherActor var NAME: Int", "@Other.Input var NAME: Int",
            "@Input @_InnoDIProvideAccessor var NAME: Int",
            "@Input @_InnoDISubContainerAccessor var NAME: Int",
            "@SubContainer nonisolated var NAME: Int",
        ]
        for shape in unsupported {
            for name in ["service", "unrelated"] {
                for mainActor in [false, true] {
                    let sibling = shape.replacingOccurrences(of: "NAME", with: name)
                    let container = try parse("@Input var service: Int\n\(sibling)")
                    for member in variables(in: container) {
                        #expect(!hasDuplicateManagedMemberName(member, in: container, options: options(mainActor)),
                                Comment(rawValue: "\(shape), mainActor=\(mainActor)"))
                    }
                }
            }
        }
    }

    @Test("Escaped identities and non-direct declarations do not count as direct duplicates")
    func escapedAndNonDirectDeclarationsDoNotCompete() throws {
        for name in ["`service`", "`class`", "`서비스`"] {
            let container = try parse("@Input var \(name): Int\n@Input var \(name): Int")
            for member in variables(in: container) {
                #expect(!hasDuplicateManagedMemberName(member, in: container, options: options(false)))
            }
        }
        let container = try parse("""
            @Input var service: Int
            #if FLAG
            @Input var service: Int
            #else
            @SubContainer var service: Child
            #endif
            struct Nested { @Input var service: Int }
            func local() { @Input var service: Int }
            """)
        let member = try #require(variables(in: container).first)
        #expect(!hasDuplicateManagedMemberName(member, in: container, options: options(false)))
    }

    @Test("Main actor policy excludes nonisolated providers from duplicate identity")
    func mainActorPolicyChangesEligibility() throws {
        let container = try parse("@Input var service: Int\n@Input nonisolated var service: Int")
        for member in variables(in: container) {
            #expect(hasDuplicateManagedMemberName(member, in: container, options: options(false)))
            #expect(!hasDuplicateManagedMemberName(member, in: container, options: options(true)))
        }
    }

    private func parse(_ members: String) throws -> StructDeclSyntax {
        let source = Parser.parse(source: "@DIContainer struct Container {\n\(members)\n}")
        return try #require(source.statements.first?.item.as(StructDeclSyntax.self))
    }

    private func variables(in container: StructDeclSyntax) -> [VariableDeclSyntax] {
        container.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
    }

    private func options(_ mainActor: Bool) -> DIContainerAttributeInfo {
        DIContainerAttributeInfo(root: false, validateDAG: true, mainActor: mainActor)
    }
}
