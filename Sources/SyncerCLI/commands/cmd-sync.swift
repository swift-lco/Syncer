import Arguments

enum SyncCommand: ParsedArgumentCommand {
    typealias Options = SyncOptions

    static let name = "sync"

    static func components() throws -> [CommandComponentLowerable] {
        [
            about("Rsync-based directory sync."),
            try params(Options.self),
        ]
    }

    static func run(
        _ options: SyncOptions,
        invocation: ParsedInvocation
    ) async throws {
        try await SyncRunner.run(
            options
        )
    }
}
