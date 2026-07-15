public enum MigrationMode: Sendable, Equatable {
    case check
    case write
}

public struct MigrationOptions: Sendable, Equatable {
    public let rootPath: String
    public let mode: MigrationMode

    public init(rootPath: String, mode: MigrationMode) {
        self.rootPath = rootPath
        self.mode = mode
    }
}

public enum MigrationArgumentError: Error, Sendable, Equatable, CustomStringConvertible {
    case duplicateOption(String)
    case missingOptionValue(String)
    case missingRoot
    case missingMode
    case mutuallyExclusiveModes
    case unexpectedArgument(String)
    case unknownOption(String)

    public var description: String {
        switch self {
        case .duplicateOption(let option):
            "Option may be specified only once: \(option)"
        case .missingOptionValue(let option):
            "Missing value for option: \(option)"
        case .missingRoot:
            "--root <path> is required."
        case .missingMode:
            "Exactly one of --check or --write is required."
        case .mutuallyExclusiveModes:
            "--check and --write are mutually exclusive."
        case .unexpectedArgument(let value):
            "Unexpected positional argument: \(value)"
        case .unknownOption(let option):
            "Unknown option: \(option)"
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
    var writeCount = 0
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
        case "--write":
            writeCount += 1
            guard writeCount == 1 else {
                return .failure(.duplicateOption("--write"))
            }
            index += 1
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
    guard checkCount + writeCount > 0 else {
        return .failure(.missingMode)
    }
    guard checkCount + writeCount == 1 else {
        return .failure(.mutuallyExclusiveModes)
    }

    return .options(
        MigrationOptions(
            rootPath: rootPath,
            mode: checkCount == 1 ? .check : .write
        )
    )
}
