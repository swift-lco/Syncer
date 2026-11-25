import ArgumentParser

struct SyncerApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "syncer",
        abstract: "Rsync-based directory sync.",
        subcommands: [
            SyncCommand.self,
            PlanCommand.self,
            HostsCommand.self,
        ],
        defaultSubcommand: SyncCommand.self
    )
}
