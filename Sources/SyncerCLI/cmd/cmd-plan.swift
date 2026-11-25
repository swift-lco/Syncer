import ArgumentParser
import Syncer

/// Prints what a route would run (rsync commands, then hooks) without running anything.
struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Print a route's rsync commands and hooks without running them."
    )

    @Argument(help: "Route name or alias. Omit with --all.")
    var route: String?

    @Flag(help: "Every route.")
    var all: Bool = false

    func run() async throws {
        let routes: [Sync.Route]
        if all {
            routes = try SyncerRoutes.all().sorted { $0.name < $1.name }
        } else {
            guard let route else {
                throw ValidationError("Name a route, or pass --all.")
            }
            guard let selected = try SyncerRoutes.byName(route) else {
                throw ValidationError("No route named '\(route)'.")
            }
            routes = [selected]
        }

        for route in routes {
            print("== \(route.name) aliases=\(route.aliases) delete=\(route.deletesExtraneous)")
            for command in Sync.plan(route).commands {
                print("   \(command.prettyLine)")
            }
            for hook in route.hooks {
                print("   hook \(hook.target) sudo=\(hook.requiresSudo) shell=\(hook.shell) \(hook.shellOptions) :: \(hook.line)")
            }
        }
    }
}
