import Errors
import Syncer
import TestFlows

@main
struct SyncerTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: SyncerTestSuite.self
        )
    }
}

enum SyncerTestSuite: TestFlowRegistry {
    static let title = "Syncer"

    static let route = Sync.Route(
        name: "deploy",
        aliases: ["ship"],
        deletesExtraneous: true,
        batches: [
            .init(
                sources: ["/srv/work/service"],
                destinations: [.init(host: "server-a", directory: "/srv/deploy/")],
                requiresSudo: true,
                excludes: [".build/", ".git/", ".build/"]
            ),
        ]
    )

    static let flows: [TestFlow] = engineFlows + SyncerFrameFlows.flows + PreflightTreeFlows.flows

    static let engineFlows: [TestFlow] = [
        TestFlow("route-matching", tags: ["routes"]) {
            try Expect.true(route.matches("deploy"), "name")
            try Expect.true(route.matches("ship"), "alias")
            try Expect.false(route.matches("dep"), "no prefix matching")
            try Expect.equal(route.allNames, ["deploy", "ship"], "all names")
            return []
        },

        TestFlow("plan-remote-arguments", tags: ["plan"]) {
            let plan = Sync.plan(route)
            try Expect.equal(plan.entries.count, 1, "one source × one destination")
            let arguments = plan.commands[0].arguments

            try Expect.true(arguments.contains("rsync"), "runs rsync")
            try Expect.true(arguments.contains("--delete"), "route deletes extraneous files")
            try Expect.true(arguments.contains("/srv/work/service"), "source as given")
            try Expect.true(arguments.contains("server-a:/srv/deploy/"), "remote destination host:path")
            try Expect.equal(
                arguments.filter { $0.contains(".build/") }.count,
                1,
                "a repeated exclude is passed once"
            )
            try Expect.true(arguments.contains { $0.contains(".git/") }, "every exclude is passed")
            return [.field("command", plan.commands[0].prettyLine)]
        },

        TestFlow("plan-delete-override", tags: ["plan"]) {
            let kept = Sync.plan(route, includeDeleteOverride: false)
            try Expect.false(kept.commands[0].arguments.contains("--delete"), "override keeps extraneous files")
            return []
        },

        TestFlow("plan-local-destination", tags: ["plan"]) {
            let local = Sync.Route(
                name: "copy",
                batches: [.init(sources: ["/srv/a"], destinations: [.init(directory: "/srv/b/")])]
            )
            let arguments = Sync.plan(local).commands[0].arguments
            try Expect.true(arguments.contains("/srv/b"), "local destination path")
            try Expect.false(arguments.contains { $0.contains(":/srv/b") }, "no host prefix")
            try Expect.false(arguments.contains("--delete"), "no delete by default")
            return []
        },

        // Current behaviour, pinned: local paths go through expandingTildeInPath,
        // which drops a trailing slash, so a "contents of" source (`dir/`) syncs
        // the directory itself. Contents sources need this changed (task 04).
        TestFlow("local-paths-drop-trailing-slash", tags: ["plan", "known-behaviour"]) {
            let contents = Sync.Route(
                name: "contents",
                batches: [.init(sources: ["/srv/a/"], destinations: [.init(host: "server-a", directory: "/srv/b/")])]
            )
            let arguments = Sync.plan(contents).commands[0].arguments
            try Expect.true(arguments.contains("/srv/a"), "local source loses its trailing slash")
            try Expect.false(arguments.contains("/srv/a/"), "no contents form")
            try Expect.true(arguments.contains("server-a:/srv/b/"), "remote destination keeps it")
            return []
        },

        TestFlow("sync-error-semantics", tags: ["errors"]) {
            let failed = SyncError.commandFailed(commandLine: "rsync -a /srv/a server-a:/srv/b/", exitCode: 23)
            try Expect.equal(SyncError.errorNamespace, "sync", "namespace")
            try Expect.equal(failed.errorCode, "command_failed", "code")
            try Expect.equal(failed.errorDisposition, .permanent, "disposition")
            try Expect.equal(failed.errorPresentation.message, "rsync failed.", "message")
            try Expect.true(
                failed.errorDiagnosticFields.contains { $0.name == "command" && $0.sensitivity == .potentially_sensitive },
                "the command line is potentially sensitive"
            )
            try Expect.equal(SyncError.hookFailed(hookLine: "true", exitCode: 1).errorCode, "hook_failed", "hook code")
            return []
        },
    ]
}
