//
//  SwiftKeywordSets.swift
//  InnoDICore
//
//  Shared Swift keyword sets used by macro validation, fix-it construction,
//  and migration. Keeping them here prevents per-target copies from drifting
//  independently — the two sets deliberately differ, so pick by semantics:
//
//  - `swiftReservedKeywords` is the strict set, including contextual
//    keywords such as `actor`, `any`, `package`, and `some`. Use it when a
//    generated helper or alias name should reject anything that reads as a
//    keyword, even where Swift would technically accept the identifier.
//  - `swiftEscapeRequiredKeywords` contains only words that cannot be
//    written as a plain property identifier without backticks. Contextual
//    keywords are deliberately absent because `var package: ...` or
//    `var actor: ...` compile fine, so a fix-it may safely suggest the
//    unescaped spelling.
//

/// Strict keyword set for generated-name and alias validation, including
/// contextual keywords.
public let swiftReservedKeywords: Set<String> = [
    "associatedtype", "actor", "any", "as", "await", "break", "case", "catch",
    "class", "continue", "default", "defer", "deinit", "do", "else", "enum",
    "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard",
    "if", "import", "in", "init", "inout", "internal", "is", "isolated", "let",
    "macro", "nil", "nonisolated", "open", "operator", "package", "precedencegroup",
    "private", "protocol", "public", "repeat", "rethrows", "return", "self",
    "Self", "some", "static", "struct", "subscript", "super", "switch", "throw",
    "throws", "true", "try", "typealias", "var", "where", "while",
]

/// Words that cannot appear as a plain (unescaped) property identifier.
/// Used to filter fix-it rename candidates: suggesting one of these as a raw
/// spelling would produce code that still needs backticks.
public let swiftEscapeRequiredKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "open",
    "operator", "private", "precedencegroup", "protocol", "public", "rethrows",
    "static", "struct", "subscript", "typealias", "var", "break", "case",
    "catch", "continue", "default", "defer", "do", "else", "fallthrough",
    "for", "guard", "if", "in", "repeat", "return", "throw", "switch",
    "where", "while", "as", "Any", "false", "is", "nil",
    "super", "self", "Self", "throws", "true", "try",
]
