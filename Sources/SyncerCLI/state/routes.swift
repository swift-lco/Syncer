import Syncer
import SyncerFrame

/// The routes of this machine, from ~/.config/syncer/routes.frame (SyncerFrame).
enum SyncerRoutes {
    static func all() throws -> [Sync.Route] {
        try SyncerConfiguration.load()
    }

    static func byName(
        _ name: String
    ) throws -> Sync.Route? {
        try all().first {
            $0.matches(name)
        }
    }

    static func names() throws -> [String] {
        try all().map { route in
            if route.aliases.isEmpty {
                return route.name
            } else {
                return "\(route.name) (\(route.aliases.joined(separator: ", ")))"
            }
        }
        .sorted()
    }
}
