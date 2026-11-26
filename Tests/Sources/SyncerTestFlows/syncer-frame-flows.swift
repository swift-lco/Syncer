import Errors
import Foundation
import Partition
import PartitionFrame
import Syncer
import SyncerFrame
import TestFlows

/// Routes from Frame configuration (SyncerFrame), with placeholder hosts and paths.
enum SyncerFrameFlows {
    static let partitions: Partitions = {
        try! PartitionConfiguration.parse(
            addresses: """
            import Partition;
            let addresses: Addresses = .{ .entries = [
                .{ .key = "work" },
                .{ .key = "service", .parent = "work" },
            ] };
            """,
            map: """
            import Partition;
            let map: Map = .{ .machine = "test-host", .root = "/srv/home", .entries = [
                .{ .key = "work", .paths = ["work"] },
                .{ .key = "service", .paths = ["work/service"] },
            ] };
            """,
            hostname: "test-host",
            exists: { _ in false }
        )
    }()

    static let main = """
    import Syncer;

    let routes: Routes = .{ .entries = [
        .{ .name = "deploy", .aliases = ["ship"], .deletes_extraneous = true, .batches = [
            .{ .sources = [ .{ .partition = "service" }, "/srv/static" ],
               .destinations = [ .{ .host = "server-a", .directory = "/srv/deploy/" } ],
               .requires_sudo = true,
               .excludes = [".git/"] },
        ], .hooks = [
            .{ .host = "server-a", .command = "restart-service", .cwd = "/srv/deploy", .shell = "zsh", .shell_options = ["-lc"] },
        ] },
        .{ .name = "conf", .batches = [
            .{ .sources = [ .{ .partition = "work", .path = "conf/app.conf" } ],
               .destinations = [ .{ .directory = "/srv/conf/" } ] },
        ] },
    ] };
    """

    /// Parses `source`, reading included files from `files`.
    static func loaded(
        _ source: String,
        files: [String: String] = [:]
    ) throws -> [Sync.Route] {
        try SyncerConfiguration.parse(
            source,
            path: "/cfg/routes.frame",
            partitions: partitions,
            read: { url in
                guard let text = files[url.standardizedFileURL.path] else {
                    throw SyncerConfigurationError.missing(file: url.path)
                }
                return text
            }
        )
    }

    static func configurationError(
        _ label: String,
        _ body: () throws -> Void
    ) throws -> SyncerConfigurationError {
        do {
            try body()
        } catch let error as SyncerConfigurationError {
            return error
        } catch {
            throw TestFlowAssertionFailure(label: label, message: "expected a SyncerConfigurationError, got \(error)")
        }
        throw TestFlowAssertionFailure(label: label, message: "nothing was thrown")
    }

    static let flows: [TestFlow] = [
        TestFlow("frame-routes", tags: ["frame"]) {
            let routes = try loaded(main)
            try Expect.equal(routes.map(\.name), ["deploy", "conf"], "both routes, in order")

            let deploy = routes[0]
            try Expect.equal(deploy.aliases, ["ship"], "aliases")
            try Expect.true(deploy.deletesExtraneous, "delete flag")
            try Expect.equal(deploy.batches[0].sources, ["/srv/home/work/service", "/srv/static"], "partition source, then path source")
            try Expect.true(deploy.batches[0].requiresSudo, "sudo")
            try Expect.equal(deploy.batches[0].excludes, [".git/"], "excludes")

            let hook = deploy.hooks[0]
            try Expect.equal(hook.target, .remote(host: "server-a", cwd: "/srv/deploy"), "remote hook")
            try Expect.equal(hook.shell, "zsh", "hook shell")
            try Expect.equal(hook.line, "restart-service", "hook command")

            try Expect.equal(routes[1].batches[0].sources, ["/srv/home/work/conf/app.conf"], "path inside a partition key")
            try Expect.equal(routes[1].batches[0].destinations[0].host, nil, "local destination")
            return []
        },

        TestFlow("frame-include", tags: ["frame", "include"]) {
            let shared = """
            import Syncer;
            let routes: Routes = .{ .entries = [
                .{ .name = "shared", .batches = [ .{ .sources = ["/srv/a"], .destinations = [ .{ .directory = "/srv/b" } ] } ] },
            ] };
            """
            let local = """
            import Syncer;
            let routes: Routes = .{ .entries = [
                .{ .name = "local", .batches = [ .{ .sources = ["/srv/c"], .destinations = [ .{ .directory = "/srv/d" } ] } ] },
            ] };
            """
            let root = """
            import Syncer;
            let routes: Routes = .{ .include = ["@service/conf/routes.frame", "more/local.frame"] };
            """
            let routes = try loaded(root, files: [
                "/srv/home/work/service/conf/routes.frame": shared,
                "/cfg/more/local.frame": local,
            ])
            try Expect.equal(routes.map(\.name), ["shared", "local"], "@key include, then relative include")
            return []
        },

        TestFlow("frame-common-excludes", tags: ["frame", "include"]) {
            let included = """
            import Syncer;
            let routes: Routes = .{ .excludes = ["*.log"], .entries = [
                .{ .name = "inner", .batches = [ .{ .sources = ["/srv/a"], .destinations = [ .{ .directory = "/srv/b" } ], .excludes = [".git/"] } ] },
            ] };
            """
            let root = """
            import Syncer;
            let routes: Routes = .{ .include = ["inner.frame"], .excludes = [".cache/", ".git/"], .entries = [
                .{ .name = "outer", .batches = [ .{ .sources = ["/srv/c"], .destinations = [ .{ .directory = "/srv/d" } ], .excludes = [".git/", "tmp/"] } ] },
            ] };
            """
            let routes = try loaded(root, files: ["/cfg/inner.frame": included])
            try Expect.equal(routes.map(\.name), ["inner", "outer"], "included route first")
            try Expect.equal(routes[0].batches[0].excludes, [".cache/", ".git/", "*.log"], "including file's, then the file's own, then the batch's; no repeats")
            try Expect.equal(routes[1].batches[0].excludes, [".cache/", ".git/", "tmp/"], "file's excludes before the batch's")
            return []
        },

        TestFlow("frame-duplicate-route", tags: ["frame", "errors"]) {
            let twice = """
            import Syncer;
            let routes: Routes = .{ .entries = [
                .{ .name = "a", .batches = [] },
                .{ .name = "b", .aliases = ["a"], .batches = [] },
            ] };
            """
            let error = try configurationError("duplicate") { _ = try loaded(twice) }
            try Expect.equal(error.errorCode, "duplicate_route", "alias equal to a name is a duplicate")
            try Expect.equal(error.errorDisposition, .requires_configuration, "disposition")
            return []
        },

        TestFlow("frame-include-cycle", tags: ["frame", "errors"]) {
            let loop = """
            import Syncer;
            let routes: Routes = .{ .include = ["routes.frame"] };
            """
            let error = try configurationError("cycle") {
                _ = try loaded(loop, files: ["/cfg/routes.frame": loop])
            }
            try Expect.equal(error.errorCode, "include_cycle", "a file including itself")
            return []
        },
    ]
}
