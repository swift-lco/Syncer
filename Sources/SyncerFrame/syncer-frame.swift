import Frame
import Syncer

/// The `Syncer` Frame module: what `import Syncer;` makes nameable in a routes file.
///
///     import Syncer;
///
///     let routes: Routes = .{
///         .include = ["@service/conf.d/syncer/deploy.frame"],
///         .excludes = [".DS_Store"],
///         .entries = [
///             .{ .name = "site", .aliases = ["web"], .deletes_extraneous = true, .batches = [
///                 .{
///                     .sources = [ .{ .partition = "websites", .path = "example-site" } ],
///                     .destinations = [ .{ .host = "web-host", .directory = "/var/www/" } ],
///                     .requires_sudo = true,
///                     .chown = "www-data:www-data",
///                     .excludes = [".git/"],
///                 },
///             ], .hooks = [
///                 .{ .host = "web-host", .command = "systemctl reload nginx", .requires_sudo = true },
///             ] },
///         ],
///     };
///
/// A source is a path (`"/srv/data"`, `"~/notes"`) or a partition key with an
/// optional path inside it. `include` adds the routes of other files; a path
/// starting with `@key/` is inside that partition key, a relative path is next
/// to the including file. A file holding only `include` stands in for another.
/// `excludes` on `Routes` applies to every batch in the file and in the files
/// it includes, before the batch's own excludes.
public enum SyncerFrame {
    public static let module = Frame.Module("Syncer", types: [
        .decodable(Routes.self, named: "Routes"),
        .decodable(Route.self, named: "Route"),
        .decodable(Batch.self, named: "Batch"),
        .decodable(Source.self, named: "Source"),
        .decodable(Destination.self, named: "Destination"),
        .decodable(Hook.self, named: "Hook"),
    ])

    public static let environment = Frame.Environment([module])

    public struct Routes: Sendable, Hashable, Decodable {
        public let include: [String]?
        /// Excluded from every batch in this file and in the files it includes.
        public let excludes: [String]?
        public let entries: [Route]?
    }

    public struct Route: Sendable, Hashable, Decodable {
        public let name: String
        public let aliases: [String]?
        public let deletes_extraneous: Bool?
        public let batches: [Batch]
        public let hooks: [Hook]?
    }

    public struct Batch: Sendable, Hashable, Decodable {
        public let sources: [Source]
        public let destinations: [Destination]
        public let requires_sudo: Bool?
        public let chown: String?
        public let excludes: [String]?
    }

    /// `"/srv/data"`, or `.{ .partition = "websites", .path = "example-site" }`.
    public enum Source: Sendable, Hashable, Decodable {
        case path(String)
        case partition(key: String, path: String?)

        private enum CodingKeys: String, CodingKey {
            case partition
            case path
        }

        public init(
            from decoder: any Decoder
        ) throws {
            if let path = try? decoder.singleValueContainer().decode(String.self) {
                self = .path(path)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = .partition(
                key: try container.decode(String.self, forKey: .partition),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        }
    }

    /// No host: a local directory.
    public struct Destination: Sendable, Hashable, Decodable {
        public let host: String?
        public let directory: String
    }

    /// Runs after the route's batches. No host: on this machine.
    public struct Hook: Sendable, Hashable, Decodable {
        public let host: String?
        public let command: String
        public let cwd: String?
        public let requires_sudo: Bool?
        public let shell: String?
        public let shell_options: [String]?
    }
}
