import ANSI
import Difference
import Foundation
import Primitives
import Syncer

/// The preflight as one tree of the paths rsync would touch. Folders that
/// don't fit the line budget are folded into one row with their counts, so
/// nothing is dropped; `full` prints every row.
enum SyncPreflightRenderer {
    /// Rows kept before folders fold.
    static let lineBudget = 80

    static func print(
        _ report: Sync.Preflight.Report,
        full: Bool = false
    ) {
        let summary = report.summary

        Swift.print("Preflight result:".ansi(.brightBlack))
        Swift.print("    commands:       \(report.results.count)")
        Swift.print("    created:        \(summary.created)")
        Swift.print("    transfers:      \(summary.transferItems.count)")
        Swift.print("    metadata-only:  \(summary.metadataItems.count)")
        Swift.print("    ignored:        \(summary.ignored)")
        Swift.print("    deleted:        \(summary.deleted)")
        Swift.print("    planned size:   \(bytes(summary.plannedBytes))")

        let tree = report.tree()
        guard !tree.roots.isEmpty else {
            Swift.print()
            return
        }

        let shown = full ? tree : Sync.Preflight.folded(tree, lines: lineBudget)
        var entries: [String: Sync.Preflight.Entry] = [:]
        collect(shown.roots, into: &entries)

        Swift.print()
        Swift.print(
            "Changes:".ansi(.brightBlack)
                + "  " + "+ new".ansi(.green)
                + "  " + "~ changed".ansi(.yellow)
                + "  " + "~ metadata".ansi(.brightBlack)
                + "  " + "- deleted".ansi(.red)
        )

        let plan = TreeDifferenceRenderPlan.make(
            TreeDifferenceLayout.make(Sync.Preflight.difference(shown))
        )
        var folded = 0
        for line in plan.lines {
            guard let entry = entries[line.id] else {
                continue
            }
            if entry.isFolded {
                folded += 1
            }
            let branch = line.segments.first { $0.component == .branch }?.text ?? ""
            Swift.print("    " + marker(entry) + " " + branch.ansi(.brightBlack) + label(entry, isRoot: branch.isEmpty))
        }

        if folded > 0 {
            Swift.print()
            Swift.print("    \(folded) folders folded (▸); --full shows every path.".ansi(.brightBlack))
        }

        Swift.print()
    }

    private static func collect(
        _ nodes: [Tree<Sync.Preflight.Entry>.Node],
        into entries: inout [String: Sync.Preflight.Entry]
    ) {
        for node in nodes {
            entries[node.value.id] = node.value
            collect(node.children, into: &entries)
        }
    }

    private static func color(
        _ entry: Sync.Preflight.Entry
    ) -> ANSIColor? {
        if entry.item?.kind == .metadata {
            return .brightBlack
        }
        switch entry.change {
        case .added: return .green
        case .removed: return .red
        case .modified, .moved, .moved_modified:
            if entry.item == nil, entry.counts.metadata == entry.counts.total {
                return .brightBlack
            }
            return .yellow
        case .unchanged: return nil
        }
    }

    private static func marker(
        _ entry: Sync.Preflight.Entry
    ) -> String {
        let text: String
        switch entry.change {
        case .added: text = "+"
        case .removed: text = "-"
        case .unchanged: text = " "
        default: text = "~"
        }
        return color(entry).map { text.ansi($0) } ?? text
    }

    private static func label(
        _ entry: Sync.Preflight.Entry,
        isRoot: Bool
    ) -> String {
        var name = entry.isFolder ? entry.name + "/" : entry.name
        if let target = entry.item?.linkTarget {
            name += " -> " + target
        }
        if entry.isFolded {
            name = "▸ " + name
        }
        let colored = entry.isFolder
            ? name.ansi(.bold)
            : (color(entry).map { name.ansi($0) } ?? name)

        var details: [String] = []
        if entry.isFolder {
            if entry.isFolded || isRoot {
                details.append(counts(entry.counts))
            }
        } else if let item = entry.item {
            if let size = item.size {
                details.append(bytes(size))
            }
            let reasons = item.reasons.map(\.rawValue).filter { $0 != item.kind.rawValue }
            if !reasons.isEmpty {
                details.append("[" + reasons.joined(separator: ", ") + "]")
            }
        }
        guard !details.isEmpty else {
            return colored
        }
        return colored + "  " + details.joined(separator: "  ").ansi(.brightBlack)
    }

    private static func counts(
        _ counts: Sync.Preflight.Counts
    ) -> String {
        var parts: [String] = []
        if counts.created > 0 { parts.append("+\(counts.created)") }
        if counts.transfer > 0 { parts.append("~\(counts.transfer)") }
        if counts.metadata > 0 { parts.append("meta \(counts.metadata)") }
        if counts.deleted > 0 { parts.append("-\(counts.deleted)") }
        if counts.other > 0 { parts.append("other \(counts.other)") }
        if counts.bytes > 0 { parts.append(bytes(counts.bytes)) }
        return parts.joined(separator: " ")
    }

    static func bytes(
        _ value: Int
    ) -> String {
        guard value > 0 else {
            return "0 B"
        }

        let units = [
            "B",
            "KB",
            "MB",
            "GB",
            "TB"
        ]

        var size = Double(value)
        var index = 0

        while size >= 1024,
              index < units.count - 1 {
            size /= 1024
            index += 1
        }

        if index == 0 {
            return "\(Int(size)) \(units[index])"
        }

        return String(
            format: "%.1f %@",
            size,
            units[index]
        )
    }
}
