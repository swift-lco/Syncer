import Syncer

/// Prints what routes would run (rsync commands, then hooks) without running anything.
enum PlanRunner {
    static func run(
        _ options: PlanOptions
    ) throws {
        let routes: [Sync.Route]
        switch options.selection {
        case .all:
            routes = try SyncerRoutes.all().sorted { $0.name < $1.name }
        case .route(let name):
            guard let selected = try SyncerRoutes.byName(name) else {
                throw SyncerCLIError.unknownRoute(name)
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
