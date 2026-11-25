import Foundation
import ArgumentParser
import Interfaces
import Syncer
import Difference

import Terminal
import ANSI

actor LastResultBox {
    private var value: Shell.Result?

    func set(_ result: Shell.Result) {
        value = result
    }

    func get() -> Shell.Result? {
        value
    }
}

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Rsync-based directory sync."
    )

    @Argument(help: "Route name to execute. Use --list to see routes.")
    var route: String?

    @Flag(name: [.customShort("l"), .customLong("list")], help: "List available routes.")
    var listRoutes: Bool = false

    @Flag(help: "Pass --dry-run to rsync.")
    var dryRun: Bool = false

    @Flag(help: "Override route setting to include --delete.")
    var delete: Bool = false

    @Flag(help: "Override route setting to exclude --delete.")
    var noDelete: Bool = false

    @Flag(name: [.customShort("v"), .long], help: "Stream rsync output live.")
    var verbose: Bool = false

    @Flag(help: "Reveal the sent commands in rsync")
    var revealCommands: Bool = false

    @Flag(help: "Skip route post-sync hooks.")
    var skipPostSync: Bool = false

    @Flag(help: "Skip preflight confirmation before real rsync.")
    var skipPreflight: Bool = false

    @Flag(help: "Render text diffs for preflight create, transfer, and delete items.")
    var diff: Bool = false

    @Flag(help: "Disable remote snapshot reads while rendering diffs.")
    var diffLocalOnly: Bool = false

    @Option(help: "Maximum number of preflight diffs to render.")
    var diffLimit: Int = 10

    @Option(help: "Maximum file size in bytes for each diff snapshot.")
    var diffMaximumBytes: Int = 512_000

    @Option(
        name: .customLong("diff-path"),
        parsing: .upToNextOption,
        help: "Only render diffs for these preflight item paths. Supports suffix matching."
    )
    var diffPaths: [String] = []

    @Flag(help: "Use rsync's size+mtime quick-check instead of checksum comparison.")
    var quickCheck: Bool = false

    @Flag(help: "Preserve file modification times instead of ignoring timestamp-only drift.")
    var preserveTimes: Bool = false

    @Option(
        name: [
            .customShort("f"),
            .customLong("raw"),
            .customLong("extra-flags"),
        ],
        parsing: .upToNextOption,
        help: "Unsafe raw rsync args. Example: --raw --itemize-changes"
    )
    var raw: [String] = []

    func run() async throws {
        if listRoutes {
            try SyncerRoutes.names().forEach {
                print($0)
            }

            return
        }

        guard let routeName = route else {
            throw ValidationError("Missing route name. Use --list to see stored routes.")
        }

        guard let selected = try SyncerRoutes.byName(routeName) else {
            throw ValidationError("Unknown route '\(routeName)'. Use --list.")
        }

        if diff,
           skipPreflight,
           !dryRun {
            throw ValidationError("--diff requires preflight. Remove --skip-preflight or use --dry-run.")
        }

        let deleteOverride: Bool? = {
            if delete && noDelete { return nil }
            if delete { return true }
            if noDelete { return false }
            return nil
        }()

        let planOptions = Sync.PlanOptions(
            comparison: quickCheck ? .quickCheck : .checksum,
            metadata: preserveTimes ? .preserve : .contentOnly,
            raw: raw
        )

        let planned = Sync.plan(
            selected,
            options: planOptions,
            includeDeleteOverride: deleteOverride
        )

        print()
        print("Route:".ansi(.brightBlack))
        print("    \(selected.name)")
        print()

        if revealCommands {
            print("Commands:".ansi(.brightBlack))
            planned.commands.forEach {
                print("\($0.prettyMultiline())\n")
            }
            print()
        }

        let spinner = LiveSpinner()
        let lastResult = LastResultBox()

        let policy: Sync.OutputPolicy = verbose ? .verbose : .quietUntilFailure

        let resolvedRoute: Sync.Route = {
            if skipPostSync {
                return .init(
                    name: selected.name,
                    deletesExtraneous: selected.deletesExtraneous,
                    batches: selected.batches,
                    hooks: []
                )
            }

            return selected
        }()

        let mode: Sync.Mode = {
            if dryRun {
                return .preflight
            }

            if skipPreflight {
                return .direct
            }

            return .gated
        }()

        if dryRun {
            print("Dry run:".ansi(.brightBlack))
            print("    rsync only, content checksum check, timestamp-only drift ignored, no hooks, no real sync")
            print()
        } else if !skipPreflight {
            print("Preflight:".ansi(.brightBlack))
            print("    dry-run rsync, content checksum check, timestamp-only drift ignored, no hooks")
            print()
        }

        do {
            let result = try await Sync.run(
                resolvedRoute,
                options: .init(
                    mode: mode,
                    execution: .init(
                        plan: planOptions,
                        dryRun: false,
                        shell: .init(.path("/usr/bin/env")),
                        cwd: nil,
                        output: policy,
                        onEvent: { event in
                            switch event {

                            case let .commandStarted(command, index, total):
                                guard !verbose else { return }
                                let label = SyncUI.label(for: command)
                                await spinner.start(line: "Syncing \(index + 1)/\(total): \(label)")

                            case let .commandFinished(command, result):
                                await lastResult.set(result)
                                guard !verbose else { return }
                                let label = SyncUI.label(for: command)
                                let meta = SyncUI.summaryLine(for: result)
                                await spinner.stop(
                                    replaceWith: "✔︎ \(label) \(meta)".ansi(.green)
                                )

                            case let .hookStarted(hook, index, total):
                                guard !verbose else { return }
                                await spinner.start(
                                    line: "Hooks (post-sync): \(index + 1)/\(total): \(hook.line)")

                            case let .hookFinished(hook, result):
                                await lastResult.set(result)
                                guard !verbose else { return }
                                let meta = SyncUI.summaryLine(for: result)
                                await spinner.stop(
                                    replaceWith: "✔︎ Hooks (executed): \(hook.line) \(meta)".ansi(.green)
                                )
                            }
                        }
                    ),
                    includeDeleteOverride: deleteOverride
                ),
                shouldRun: { report in
                    SyncPreflightRenderer.print(
                        report
                    )

                    await renderDiffs(
                        from: report
                    )

                    guard Terminal.confirm(
                        "Proceed with real sync?",
                        default: .no
                    ) else {
                        print("Cancelled.".ansi(.yellow))
                        return false
                    }

                    print()

                    return true
                }
            )

            if dryRun,
               let report = result.preflight {
                SyncPreflightRenderer.print(
                    report
                )

                await renderDiffs(
                    from: report
                )
            }
        } catch {
            if !verbose {
                await spinner.stop(replaceWith: "✖ Sync failed".ansi(.red))
                if let r = await lastResult.get() {
                    let out = r.stdoutText()
                    let err = r.stderrText()
                    if !out.isEmpty { print(out) }
                    if !err.isEmpty { fputs(err + "\n", stderr) }
                }
            }

            throw error
        }
    }
}

private extension SyncCommand {
    func renderDiffs(
        from report: Sync.Preflight.Report
    ) async {
        guard diff else {
            return
        }

        print()
        print("Diffs:".ansi(.brightBlack))

        do {
            let changes = try await Sync.Diff.changes(
                from: report,
                options: .init(
                    kinds: [
                        .created,
                        .transfer,
                        .deleted,
                    ],
                    paths: Set(diffPaths),
                    limit: max(
                        0,
                        diffLimit
                    ),
                    maximumBytes: max(
                        0,
                        diffMaximumBytes
                    ),
                    allowRemote: !diffLocalOnly,
                    shell: .init(.path("/usr/bin/env"))
                )
            )

            guard !changes.isEmpty else {
                print("    no text diffs available".ansi(.brightBlack))
                print()
                return
            }

            for change in changes {
                print()
                print(
                    "    \(change.item.kind.rawValue): \(change.item.path)".ansi(.brightBlack)
                )

                print(
                    TerminalDifferenceRenderer.render(
                        change.difference,
                        // options: .unified
                    )
                )
            }

            print()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(
                    describing: error
                )

            print(
                "    skipped: \(message)".ansi(.yellow)
            )
            print()
        }
    }
}
