import Foundation
import Interfaces

extension Sync {
    public struct Hook: Sendable, Hashable {
        public enum Target: Sendable, Hashable {
            case local(cwd: String? = nil)
            case remote(host: String, cwd: String? = nil)
        }

        public var target: Target
        public var line: String
        public var requiresSudo: Bool

        public var shell: String
        public var shellOptions: [String]

        public init(
            target: Target,
            line: String,
            requiresSudo: Bool = false,
            shell: String = "sh",
            shellOptions: [String] = ["-lc"]
        ) {
            self.target = target
            self.line = line
            self.requiresSudo = requiresSudo
            self.shell = shell
            self.shellOptions = shellOptions
        }

        public static func local(
            _ line: String,
            cwd: String? = nil,
            requiresSudo: Bool = false,
            shell: String = "sh",
            shellOptions: [String] = ["-lc"]
        ) -> Hook {
            .init(
                target: .local(cwd: cwd),
                line: line,
                requiresSudo: requiresSudo,
                shell: shell,
                shellOptions: shellOptions
            )
        }

        public static func remote(
            _ host: String,
            _ line: String,
            cwd: String? = nil,
            requiresSudo: Bool = false,
            shell: String = "sh",
            shellOptions: [String] = ["-lc"]
        ) -> Hook {
            .init(
                target: .remote(host: host, cwd: cwd),
                line: line,
                requiresSudo: requiresSudo,
                shell: shell,
                shellOptions: shellOptions
            )
        }
    }
}

extension Sync {
    /// A local hook runs `env <shell> <options> <line>` directly. A remote
    /// hook goes through ssh, which joins its arguments with spaces for the
    /// remote login shell to split again; every word is quoted for that shell,
    /// so the line reaches `<shell> -c` whole (cwd included).
    public static func hookCommand(_ hook: Hook) -> Command {
        var line = hook.requiresSudo ? "sudo \(hook.line)" : hook.line

        switch hook.target {
        case let .local(cwd):
            if let cwd, !cwd.isEmpty {
                line = "cd \(shellQuoted(expandingHome(cwd))) && \(line)"
            }
            return Command(arguments: ["/usr/bin/env", hook.shell] + hook.shellOptions + [line])

        case let .remote(host, cwd):
            if let cwd, !cwd.isEmpty {
                line = "cd \(remoteDirectory(cwd)) && \(line)"
            }
            let remote = ["/usr/bin/env", hook.shell] + hook.shellOptions + [line]
            return Command(arguments: ["ssh", host] + remote.map(shellQuoted))
        }
    }

    /// One word for a POSIX shell: single-quoted, with embedded quotes escaped.
    public static func shellQuoted(
        _ word: String
    ) -> String {
        let safe = word.allSatisfy { character in
            character.isLetter || character.isNumber || "/._-+=:,@%".contains(character)
        }
        if safe, !word.isEmpty {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `~` and `~/…` stay unquoted so the remote shell expands them.
    static func remoteDirectory(
        _ cwd: String
    ) -> String {
        if cwd == "~" {
            return "~"
        }
        if cwd.hasPrefix("~/") {
            return "~/" + shellQuoted(String(cwd.dropFirst(2)))
        }
        return shellQuoted(cwd)
    }

    static func expandingHome(
        _ path: String
    ) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        return NSString(string: path).expandingTildeInPath
    }
}
