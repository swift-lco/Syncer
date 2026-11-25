import Errors
import Foundation

/// A route step that ran and failed.
public enum SyncError: Error, LocalizedError, Sendable, Equatable {
    case commandFailed(commandLine: String, exitCode: Int)
    case hookFailed(hookLine: String, exitCode: Int)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(_, let code):
            return "rsync failed (exit \(code))"
        case .hookFailed(_, let code):
            return "post-sync hook failed (exit \(code))"
        }
    }
}

extension SyncError: SemanticError, ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "sync"

    public var errorCode: String {
        switch self {
        case .commandFailed:
            return "command_failed"
        case .hookFailed:
            return "hook_failed"
        }
    }

    public var errorPresentation: ErrorPresentation {
        switch self {
        case .commandFailed(_, let code):
            return .init(
                message: "rsync failed.",
                reason: "It exited with status \(code).",
                recoverySuggestion: "Run the route with --verbose to see rsync's own output, or --dry-run to check it without changes."
            )
        case .hookFailed(_, let code):
            return .init(
                message: "A post-sync hook failed.",
                reason: "It exited with status \(code); the files were already synced.",
                recoverySuggestion: "Run the hook's command on its host to see its output."
            )
        }
    }

    /// Command lines name hosts and paths.
    public var errorDiagnosticFields: [ErrorDiagnosticField] {
        switch self {
        case .commandFailed(let line, let code):
            return [
                .init(key: "command", value: line, sensitivity: .potentially_sensitive),
                .init(key: "exit_code", value: "\(code)"),
            ]
        case .hookFailed(let line, let code):
            return [
                .init(key: "hook", value: line, sensitivity: .potentially_sensitive),
                .init(key: "exit_code", value: "\(code)"),
            ]
        }
    }

    public var errorDisposition: ErrorDisposition? {
        .permanent
    }
}
