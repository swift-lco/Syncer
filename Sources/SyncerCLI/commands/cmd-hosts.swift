import Arguments

enum HostsCommand: RunnableArgumentCommand {
    static let name = "hosts"

    static func components() throws -> [CommandComponentLowerable] {
        [about("List the hosts in ~/.ssh/config.")]
    }

    static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        HostsRunner.run()
    }
}
