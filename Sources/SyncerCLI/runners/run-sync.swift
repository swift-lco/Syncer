import ANSI
import Difference
import Foundation
import Interfaces
import Syncer
import Terminal

actor LastResultBox {
    private var value: Shell.Result?

    func set(_ result: Shell.Result) {
        value = result
    }

    func get() -> Shell.Result? {
        value
    }
}

enum SyncRunner {
    static func run(
        _ options: SyncOptions
    ) async throws {
        let routeName: String
        switch options.action {
        case .list:
            try SyncerRoutes.names().forEach {
                print($0)
            }
            return
        case .run(let route):
            routeName = route
        }

        guard let selected = try SyncerRoutes.byName(routeName) else {
            throw SyncerCLIError.unknownRoute(routeName)
        }

        let verbose = options.verbose

        let planned = Sync.plan(
            selected,
            options: options.plan,
            includeDeleteOverride: options.deleteOverride
        )

        print()
        print("Route:".ansi(.brightBlack))
        print("    \(selected.name)")
        print()

        if options.revealCommands {
            print("Commands:".ansi(.brightBlack))
            planned.commands.forEach {
                print("\($0.prettyMultiline())\n")
            }
            print()
        }

        let spinner = LiveSpinner()
        let lastResult = LastResultBox()

        let policy: Sync.OutputPolicy = verbose ? .verbose : .quietUntilFailure

        let resolvedRoute: Sync.Route = options.skipHooks
            ? .init(
                name: selected.name,
                deletesExtraneous: selected.deletesExtraneous,
                batches: selected.batches,
                hooks: []
            )
            : selected

        switch options.mode {
        case .preflight:
            print("Dry run:".ansi(.brightBlack))
            print("    rsync only, content checksum check, timestamp-only drift ignored, no hooks, no real sync")
            print()
        case .gated:
            print("Preflight:".ansi(.brightBlack))
            print("    dry-run rsync, content checksum check, timestamp-only drift ignored, no hooks")
            print()
        default:
            break
        }

        do {
            let result = try await Sync.run(
                resolvedRoute,
                options: .init(
                    mode: options.mode,
                    execution: .init(
                        plan: options.plan,
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
                    includeDeleteOverride: options.deleteOverride
                ),
                shouldRun: { report in
                    SyncPreflightRenderer.print(
                        report
                    )

                    await renderDiffs(
                        from: report,
                        options: options.diffs
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

            if options.mode == .preflight,
               let report = result.preflight {
                SyncPreflightRenderer.print(
                    report
                )

                await renderDiffs(
                    from: report,
                    options: options.diffs
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

    private static func renderDiffs(
        from report: Sync.Preflight.Report,
        options: SyncOptions.DiffOptions?
    ) async {
        guard let options else {
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
                    paths: options.paths,
                    limit: options.limit,
                    maximumBytes: options.maximumBytes,
                    allowRemote: !options.localOnly,
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
                        change.difference
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
