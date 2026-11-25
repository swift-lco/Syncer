import Arguments
import Foundation
import Syncer

/// What `syncer sync` works with, checked once.
struct SyncOptions: Sendable, ArgumentParsed {
    typealias ArgumentPayload = Payload

    enum Action: Sendable {
        case list
        case run(route: String)
    }

    let action: Action
    let mode: Sync.Mode
    /// `--delete` / `--no-delete`; nil keeps the route's setting (also when both are given).
    let deleteOverride: Bool?
    let plan: Sync.PlanOptions
    let verbose: Bool
    let revealCommands: Bool
    let skipHooks: Bool
    let diffs: DiffOptions?

    struct DiffOptions: Sendable {
        let localOnly: Bool
        let limit: Int
        let maximumBytes: Int
        let paths: Set<String>
    }

    init(
        arguments: Payload
    ) throws {
        if arguments.list {
            action = .list
        } else {
            guard !arguments.route.isEmpty else {
                throw SyncerCLIError.missingRoute
            }
            action = .run(route: arguments.route)
        }

        if arguments.diff, arguments.skipPreflight, !arguments.dryRun {
            throw SyncerCLIError.diffNeedsPreflight
        }

        mode = arguments.dryRun ? .preflight : (arguments.skipPreflight ? .direct : .gated)
        deleteOverride = switch (arguments.delete, arguments.noDelete) {
        case (true, false): true
        case (false, true): false
        default: nil
        }
        plan = Sync.PlanOptions(
            comparison: arguments.quickCheck ? .quickCheck : .checksum,
            metadata: arguments.preserveTimes ? .preserve : .contentOnly,
            raw: arguments.raw
        )
        verbose = arguments.verbose
        revealCommands = arguments.revealCommands
        skipHooks = arguments.skipPostSync
        diffs = arguments.diff
            ? DiffOptions(
                localOnly: arguments.diffLocalOnly,
                limit: max(0, arguments.diffLimit),
                maximumBytes: max(0, arguments.diffMaximumBytes),
                paths: Set(arguments.diffPaths)
            )
            : nil
    }

    struct Payload: ArgumentGroup {
        @Arg("route", help: "Route name to execute. Use --list to see routes.", default: "")
        var route: String

        @Flag("list", short: "l", help: "List available routes.")
        var list: Bool

        @Flag("dry-run", help: "Pass --dry-run to rsync.")
        var dryRun: Bool

        @Flag("delete", negation: .none, help: "Override route setting to include --delete.")
        var delete: Bool

        @Flag("no-delete", negation: .none, help: "Override route setting to exclude --delete.")
        var noDelete: Bool

        @Flag("verbose", short: "v", help: "Stream rsync output live.")
        var verbose: Bool

        @Flag("reveal-commands", help: "Reveal the sent commands in rsync.")
        var revealCommands: Bool

        @Flag("skip-post-sync", help: "Skip route post-sync hooks.")
        var skipPostSync: Bool

        @Flag("skip-preflight", help: "Skip preflight confirmation before real rsync.")
        var skipPreflight: Bool

        @Flag("diff", help: "Render text diffs for preflight create, transfer, and delete items.")
        var diff: Bool

        @Flag("diff-local-only", help: "Disable remote snapshot reads while rendering diffs.")
        var diffLocalOnly: Bool

        @Opt("diff-limit", default: 10, help: "Maximum number of preflight diffs to render.")
        var diffLimit: Int

        @Opt("diff-maximum-bytes", default: 512_000, help: "Maximum file size in bytes for each diff snapshot.")
        var diffMaximumBytes: Int

        @Opts("diff-path", take: .many, help: "Only render diffs for these preflight item paths. Supports suffix matching.")
        var diffPaths: [String]

        @Flag("quick-check", help: "Use rsync's size+mtime quick-check instead of checksum comparison.")
        var quickCheck: Bool

        @Flag("preserve-times", help: "Preserve file modification times instead of ignoring timestamp-only drift.")
        var preserveTimes: Bool

        @Opts("raw", aliases: ["extra-flags"], short: "f", take: .many, help: "Unsafe raw rsync args. Example: --raw --itemize-changes")
        var raw: [String]

        init() {}
    }
}

/// Command-line mistakes caught before anything runs.
enum SyncerCLIError: Error, LocalizedError, Sendable, Equatable {
    case missingRoute
    case unknownRoute(String)
    case diffNeedsPreflight
    case planNeedsRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "Missing route name. Use --list to see stored routes."
        case .unknownRoute(let name):
            return "Unknown route '\(name)'. Use --list."
        case .diffNeedsPreflight:
            return "--diff requires preflight. Remove --skip-preflight or use --dry-run."
        case .planNeedsRoute:
            return "Name a route, or pass --all."
        }
    }
}
