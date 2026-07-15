import Foundation
import InnoDIMigrationCore

exit(MigrationCLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
