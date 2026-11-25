import ANSI
import Syncer

enum SyncPreflightRenderer {
    static func print(
        _ report: Sync.Preflight.Report
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

        group(
            "Creates",
            items: summary.createdItems,
            color: .green,
            limit: 20
        )

        group(
            "Transfers",
            items: summary.transferItems,
            color: .yellow,
            limit: 30
        )

        group(
            "Metadata only",
            items: summary.metadataItems,
            color: .brightBlack,
            limit: 30
        )

        group(
            "Ignored",
            items: summary.ignoredItems,
            color: .brightBlack,
            limit: 30
        )

        group(
            "Deletions",
            items: summary.deletedItems,
            color: .red,
            limit: 20
        )

        group(
            "Other",
            items: summary.otherItems,
            color: .brightBlack,
            limit: 20
        )

        Swift.print()
    }

    private static func group(
        _ title: String,
        items: [Sync.Preflight.Item],
        color: ANSIColor,
        limit: Int
    ) {
        guard !items.isEmpty else {
            return
        }

        Swift.print()
        Swift.print("\(title):".ansi(color))

        for item in items.prefix(limit) {
            Swift.print("    \(line(item))")
        }

        let remaining = max(
            0,
            items.count - limit
        )

        if remaining > 0 {
            Swift.print("    ... \(remaining) more")
        }
    }

    private static func line(
        _ item: Sync.Preflight.Item
    ) -> String {
        let kind = item.fileKind.rawValue.padded(
            to: 7
        )

        let size = item.size.map(bytes) ?? "-"
        let paddedSize = size.leftPadded(
            to: 9
        )

        let reasons = item.reasons
            .map(\.rawValue)
            .joined(separator: ", ")

        if reasons.isEmpty {
            return "\(kind) \(paddedSize) \(item.path)"
        }

        return "\(kind) \(paddedSize) \(item.path) [\(reasons)]"
    }

    private static func bytes(
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

private extension String {
    func padded(
        to width: Int
    ) -> String {
        guard count < width else {
            return self
        }

        return self + String(
            repeating: " ",
            count: width - count
        )
    }

    func leftPadded(
        to width: Int
    ) -> String {
        guard count < width else {
            return self
        }

        return String(
            repeating: " ",
            count: width - count
        ) + self
    }
}
