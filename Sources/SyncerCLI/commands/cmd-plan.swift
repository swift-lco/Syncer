import Arguments

enum PlanCommand: ParsedArgumentCommand {
    typealias Options = PlanOptions

    static let name = "plan"

    static func components() throws -> [CommandComponentLowerable] {
        [
            about("Print a route's rsync commands and hooks without running them."),
            try params(Options.self),
        ]
    }

    static func run(
        _ options: PlanOptions,
        invocation: ParsedInvocation
    ) async throws {
        try PlanRunner.run(
            options
        )
    }
}
