import Foundation
import Interfaces
import Syncer

enum SyncUI {
    static func label(for command: Sync.Command) -> String {
        // Heuristic: last arg is destination (host:path or local path)
        command.arguments.last ?? command.prettyLine
    }

    static func summaryLine(for result: Shell.Result) -> String {
        let text = result.stdoutText() + "\n" + result.stderrText()
        let s = Sync.parseSummary(from: text)

        var parts: [String] = []
        if let sent = s.sentBytes { parts.append("sent \(sent)B") }
        if let recv = s.receivedBytes { parts.append("recv \(recv)B") }
        if let total = s.totalSizeBytes { parts.append("total \(total)B") }
        if let sp = s.speedup { parts.append("speedup \(sp)") }

        if parts.isEmpty {
            return result.shortSummary.ansi(.brightBlack)
        }

        return "[" + parts.joined(separator: ", ") + "]"
            .ansi(.brightBlack)
    }
}
