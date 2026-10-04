public enum MigrationMode: Sendable, Equatable {
    case check
    case report
    case write
}

public struct MigrationOptions: Sendable, Equatable {
    public let rootPath: String
    public let mode: MigrationMode
    public let outputPath: String?
    /// Imported modules the user asserts declare no InnoDI-named attributes.
    public let trustedModules: [String]
    public let swiftUIImportAccess: MigrationSwiftUIImportAccess?

    public init(
        rootPath: String,
        mode: MigrationMode,
        outputPath: String? = nil,
        trustedModules: [String] = [],
        swiftUIImportAccess: MigrationSwiftUIImportAccess? = nil
    ) {
        self.rootPath = rootPath
        self.mode = mode
        self.outputPath = outputPath
        self.trustedModules = trustedModules
        self.swiftUIImportAccess = swiftUIImportAccess
    }
}

public enum MigrationArgumentError: Error, Sendable, Equatable, CustomStringConvertible {
    case duplicateOption(String)
    case missingOptionValue(String)
    case missingRoot
    case missingMode
    case mutuallyExclusiveModes
    case outputRequiresReport
    case unexpectedArgument(String)
    case unknownOption(String)
    case invalidSwiftUIImportAccess(String)

    public var description: String {
        switch self {
        case .duplicateOption(let option):
            "Option may be specified only once: \(option)"
        case .missingOptionValue(let option):
            "Missing value for option: \(option)"
        case .missingRoot:
            "--root <path> is required."
        case .missingMode:
            "Exactly one of --check, --report, or --write is required."
        case .mutuallyExclusiveModes:
            "--check, --report, and --write are mutually exclusive."
        case .outputRequiresReport:
            "--output may be used only with --report."
        case .unexpectedArgument(let value):
            "Unexpected positional argument: \(value)"
        case .unknownOption(let option):
            "Unknown option: \(option)"
        case .invalidSwiftUIImportAccess(let value):
            "Invalid SwiftUI import access '\(value)'; use internal or public."
        }
    }
}

public enum MigrationArgumentParseResult: Sendable, Equatable {
    case options(MigrationOptions)
    case helpRequested
    case failure(MigrationArgumentError)
}

public func parseMigrationArguments(_ arguments: [String]) -> MigrationArgumentParseResult {
    if arguments.contains("--help") || arguments.contains("-h") {
        return .helpRequested
    }

    var rootPath: String?
    var checkCount = 0
    var reportCount = 0
    var writeCount = 0
    var outputPath: String?
    var trustedModules: [String] = []
    var swiftUIImportAccess: MigrationSwiftUIImportAccess?
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--root":
            guard rootPath == nil else {
                return .failure(.duplicateOption("--root"))
            }
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex),
                  !arguments[valueIndex].isEmpty,
                  !arguments[valueIndex].hasPrefix("--") else {
                return .failure(.missingOptionValue("--root"))
            }
            rootPath = arguments[valueIndex]
            index += 2
        case "--check":
            checkCount += 1
            guard checkCount == 1 else {
                return .failure(.duplicateOption("--check"))
            }
            index += 1
        case "--report":
            reportCount += 1
            guard reportCount == 1 else {
                return .failure(.duplicateOption("--report"))
            }
            index += 1
        case "--write":
            writeCount += 1
            guard writeCount == 1 else {
                return .failure(.duplicateOption("--write"))
            }
            index += 1
        case "--output":
            guard outputPath == nil else {
                return .failure(.duplicateOption("--output"))
            }
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex),
                  !arguments[valueIndex].isEmpty,
                  !arguments[valueIndex].hasPrefix("--") else {
                return .failure(.missingOptionValue("--output"))
            }
            outputPath = arguments[valueIndex]
            index += 2
        case "--swiftui-import-access":
            guard swiftUIImportAccess == nil else {
                return .failure(.duplicateOption(argument))
            }
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex),
                  !arguments[valueIndex].isEmpty,
                  !arguments[valueIndex].hasPrefix("--") else {
                return .failure(.missingOptionValue(argument))
            }
            guard let access = MigrationSwiftUIImportAccess(rawValue: arguments[valueIndex]) else {
                return .failure(.invalidSwiftUIImportAccess(arguments[valueIndex]))
            }
            swiftUIImportAccess = access
            index += 2
        case "--trust-module":
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex),
                  !arguments[valueIndex].isEmpty,
                  !arguments[valueIndex].hasPrefix("--") else {
                return .failure(.missingOptionValue("--trust-module"))
            }
            if !trustedModules.contains(arguments[valueIndex]) {
                trustedModules.append(arguments[valueIndex])
            }
            index += 2
        default:
            if argument.hasPrefix("-") {
                return .failure(.unknownOption(argument))
            }
            return .failure(.unexpectedArgument(argument))
        }
    }

    guard let rootPath else {
        return .failure(.missingRoot)
    }
    let modeCount = checkCount + reportCount + writeCount
    guard modeCount > 0 else {
        return .failure(.missingMode)
    }
    guard modeCount == 1 else {
        return .failure(.mutuallyExclusiveModes)
    }
    guard outputPath == nil || reportCount == 1 else {
        return .failure(.outputRequiresReport)
    }

    let mode: MigrationMode
    if checkCount == 1 {
        mode = .check
    } else if reportCount == 1 {
        mode = .report
    } else {
        mode = .write
    }

    return .options(
        MigrationOptions(
            rootPath: rootPath,
            mode: mode,
            outputPath: outputPath,
            trustedModules: trustedModules,
            swiftUIImportAccess: swiftUIImportAccess
        )
    )
}
