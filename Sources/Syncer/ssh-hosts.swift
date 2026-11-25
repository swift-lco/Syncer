import Foundation
import Readers

/// Host aliases declared in an ssh config (`Host <name>` lines without wildcards).
public enum SSHHosts {
    public static func list(
        from path: String = "~/.ssh/config"
    ) -> [String] {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard let text = try? TextFileReader(url).read(options: .init(missingFilePolicy: .returnEmpty)).text else {
            return []
        }

        return text
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("Host ") && !$0.contains("*") }
            .map {
                $0.replacingOccurrences(of: "Host ", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
    }
}
