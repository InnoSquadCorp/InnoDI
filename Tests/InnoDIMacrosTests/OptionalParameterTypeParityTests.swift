import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import Testing

@testable import InnoDIMacros

@Suite("Optional parameter typed construction parity")
struct OptionalParameterTypeParityTests {
    @Test("Typed wrappers preserve the previous parser-produced spelling", arguments: [
        "Int", "Swift.Int", "Int?", "Int??", "[Int]", "[String: Int?]",
        "Box<Int>", "Box<(Int, String)>", "Box<() -> Int>", "(Int, String)",
        "(value: Int, name: String)", "()", "() -> Int", "(Int) -> String",
        "@Sendable () -> Int", "@MainActor @Sendable () async throws -> Int",
        "(() -> Int)?", "((Int) -> String)?", "any Sendable", "some Sendable",
        "Sendable & Equatable", "any Sendable & Equatable", "(any Sendable)?",
        "(any Sendable & Equatable)?", "Box<any Sendable>", "Box<Sendable & Equatable>",
        "Int /* retained */", "/* leading */ Int", "Box</* inside */ Int>",
        "(Int, /* separator */ String)", "() /* arrow */ -> Int",
        "@Sendable /* attribute */ () -> Int", "(\nInt,\nString\n)",
        "Box<\nInt\n>", "  Int  ", "Self.Value", "Optional<Int>",
        "Result<Int, Failure>", "(borrowing Value) -> Int", "() throws(Failure) -> Int"
    ])
    func preservesOriginalTypeSpelling(source: String) {
        let type = TypeSyntax(stringLiteral: source)
        let trimmed = type.trimmedDescription
        let grouped = trimmed.hasPrefix("any ") || trimmed.hasPrefix("some ")
            || trimmed.contains("&") || trimmed.contains("->")
        let original = TypeSyntax(stringLiteral: grouped ? "(\(trimmed))?" : "\(trimmed)?")
        let actual = optionalParameterType(for: type)
        #expect(actual.description == original.description)
        #expect(actual.hasError == original.hasError)
        #expect(actual.tokens(viewMode: .all).map(\.text) == original.tokens(viewMode: .all).map(\.text))
    }
}
