import Arguments
import Errors
import Foundation

/// `syncer [<route>]` runs `sync`; `syncer plan`, `syncer hosts`.
@main
enum SyncerCommand: ArgumentCommand {
    typealias DefaultChild = SyncCommand

    static let name = "syncer"
    static let defaultChild = SyncCommand.self

    static let children: [ArgumentCommandType] = [
        SyncCommand.self,
        PlanCommand.self,
        HostsCommand.self,
    ]

    static func components() throws -> [CommandComponentLowerable] {
        [about("Rsync-based directory sync.")]
    }

    static func main() async {
        await ArgumentProgram.main(
            command: Self.self,
            errorHandler: { error in
                FileHandle.standardError.write(Data("Error: \(error.explanation)\n".utf8))
                return 1
            }
        )
    }
}
