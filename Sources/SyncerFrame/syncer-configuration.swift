import Errors
import Foundation
import Frame
import IO
import Partition
import PartitionFrame
import Path
import Readers
import Syncer

/// Routes from `$SYNCER_CONFIG`, else `$XDG_CONFIG_HOME/syncer/routes.frame`,
/// else `~/.config/syncer/routes.frame`, with every `include` followed.
public enum SyncerConfiguration {
    public static let environmentKey = "SYNCER_CONFIG"
    public static let fileName = "routes.frame"

    public static func file(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[environmentKey].flatMap({ $0.isEmpty ? nil : $0 }) {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base
            .appendingPathComponent("syncer", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// This machine's routes. Partition keys resolve through `partitions`,
    /// loaded from `~/.config/partition` the first time one is needed.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        partitions: Partitions? = nil
    ) throws -> [Sync.Route] {
        var loader = Loader(partitions: partitions)
        return try loader.routes(from: file(environment: environment))
    }

    /// Routes from sources already read, keyed by path; for tests and tools.
    public static func parse(
        _ source: String,
        path: String = fileName,
        partitions: Partitions? = nil,
        read: @escaping (URL) throws -> String = { try SyncerConfiguration.read($0) }
    ) throws -> [Sync.Route] {
        var loader = Loader(partitions: partitions, read: read)
        return try loader.routes(source: source, file: URL(fileURLWithPath: path))
    }

    public static func read(
        _ file: URL
    ) throws -> String {
        guard FileSystem.default.exists(file) else {
            throw SyncerConfigurationError.missing(file: file.path)
        }
        return try TextFileReader(file).read().text
    }

    struct Loader {
        var partitions: Partitions?
        var read: (URL) throws -> String = { try SyncerConfiguration.read($0) }
        var visiting: [String] = []
        var seen: [String: String] = [:]

        init(
            partitions: Partitions?,
            read: @escaping (URL) throws -> String = { try SyncerConfiguration.read($0) }
        ) {
            self.partitions = partitions
            self.read = read
        }

        mutating func routes(
            from file: URL,
            excludes inherited: [String] = []
        ) throws -> [Sync.Route] {
            try routes(source: try read(file), file: file, excludes: inherited)
        }

        mutating func routes(
            source: String,
            file: URL,
            excludes inherited: [String] = []
        ) throws -> [Sync.Route] {
            let path = file.standardizedFileURL.path
            guard !visiting.contains(path) else {
                throw SyncerConfigurationError.includeCycle(file: path)
            }
            visiting.append(path)
            defer { visiting.removeLast() }

            let decoded: SyncerFrame.Routes
            do {
                let document = try Frame.parse(source, filePath: path, environment: SyncerFrame.environment)
                decoded = try document.decode(SyncerFrame.Routes.self, binding: "routes")
            } catch {
                throw SyncerConfigurationError.invalid(file: path, message: "\(error)")
            }

            let excludes = Self.merged(inherited, decoded.excludes ?? [])
            var out: [Sync.Route] = []
            for include in decoded.include ?? [] {
                out += try routes(from: try resolve(include: include, relativeTo: file), excludes: excludes)
            }
            for route in decoded.entries ?? [] {
                for name in [route.name] + (route.aliases ?? []) {
                    if let first = seen[name] {
                        throw SyncerConfigurationError.duplicateRoute(name: name, file: path, first: first)
                    }
                    seen[name] = path
                }
                out.append(try convert(route, excludes: excludes))
            }
            return out
        }

        /// In order, without repeats.
        static func merged(
            _ first: [String],
            _ second: [String]
        ) -> [String] {
            var seen: Set<String> = []
            return (first + second).filter { seen.insert($0).inserted }
        }

        mutating func partitionPath(
            _ key: String,
            _ relative: String?
        ) throws -> String {
            if partitions == nil {
                partitions = try PartitionConfiguration.load()
            }
            return try partitions!
                .path(key, relative)
                .render(as: .root, filetype: true)
        }

        mutating func resolve(
            include: String,
            relativeTo file: URL
        ) throws -> URL {
            if include.hasPrefix("@") {
                let rest = include.dropFirst()
                let key = rest.prefix { $0 != "/" }
                let relative = rest.dropFirst(key.count).drop { $0 == "/" }
                return URL(fileURLWithPath: try partitionPath(String(key), relative.isEmpty ? nil : String(relative)))
            }
            let expanded = NSString(string: include).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return URL(fileURLWithPath: expanded)
            }
            return file.deletingLastPathComponent().appendingPathComponent(expanded)
        }

        mutating func convert(
            _ route: SyncerFrame.Route,
            excludes common: [String] = []
        ) throws -> Sync.Route {
            var batches: [Sync.Batch] = []
            for batch in route.batches {
                var sources: [String] = []
                for source in batch.sources {
                    switch source {
                    case .path(let path):
                        sources.append(NSString(string: path).expandingTildeInPath)
                    case .partition(let key, let path):
                        sources.append(try partitionPath(key, path))
                    }
                }
                batches.append(.init(
                    sources: sources,
                    destinations: batch.destinations.map { .init(host: $0.host, directory: $0.directory) },
                    requiresSudo: batch.requires_sudo ?? false,
                    chown: batch.chown,
                    excludes: Self.merged(common, batch.excludes ?? [])
                ))
            }
            let hooks: [Sync.Hook] = (route.hooks ?? []).map { hook in
                .init(
                    target: hook.host.map { .remote(host: $0, cwd: hook.cwd) } ?? .local(cwd: hook.cwd),
                    line: hook.command,
                    requiresSudo: hook.requires_sudo ?? false,
                    shell: hook.shell ?? "sh",
                    shellOptions: hook.shell_options ?? ["-lc"]
                )
            }
            return Sync.Route(
                name: route.name,
                aliases: route.aliases ?? [],
                deletesExtraneous: route.deletes_extraneous ?? false,
                batches: batches,
                hooks: hooks
            )
        }
    }
}

/// Why a routes file could not be loaded.
public enum SyncerConfigurationError: Error, LocalizedError, Sendable, Equatable {
    case missing(file: String)
    case invalid(file: String, message: String)
    case includeCycle(file: String)
    case duplicateRoute(name: String, file: String, first: String)

    public var errorDescription: String? {
        errorPresentation.message
    }
}

extension SyncerConfigurationError: SemanticError, ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "sync.configuration"

    public var errorCode: String {
        switch self {
        case .missing: return "missing"
        case .invalid: return "invalid"
        case .includeCycle: return "include_cycle"
        case .duplicateRoute: return "duplicate_route"
        }
    }

    public var errorPresentation: ErrorPresentation {
        switch self {
        case .missing(let file):
            return .init(
                message: "No routes file at \(file).",
                reason: "Routes come from configuration, not from the program.",
                recoverySuggestion: "Create it with `import Syncer;` and `let routes: Routes = .{ .entries = [...] };`, or set SYNCER_CONFIG."
            )
        case .invalid(let file, let message):
            return .init(message: "The routes file \(file) is invalid.", reason: message, recoverySuggestion: nil)
        case .includeCycle(let file):
            return .init(message: "Routes files include each other.", reason: "\(file) is reached again through its own includes.", recoverySuggestion: "Remove one of the includes.")
        case .duplicateRoute(let name, let file, let first):
            return .init(message: "Route name '\(name)' is defined twice.", reason: "In \(first) and in \(file).", recoverySuggestion: "Route names and aliases must be unique across included files.")
        }
    }

    public var errorDiagnosticFields: [ErrorDiagnosticField] {
        switch self {
        case .missing(let file), .invalid(let file, _), .includeCycle(let file):
            return [.init(key: "file", value: file, sensitivity: .potentially_sensitive)]
        case .duplicateRoute(let name, let file, _):
            return [.init(key: "route", value: name), .init(key: "file", value: file, sensitivity: .potentially_sensitive)]
        }
    }

    public var errorDisposition: ErrorDisposition? {
        .requires_configuration
    }
}
