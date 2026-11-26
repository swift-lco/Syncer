import Difference
import Primitives

extension Sync.Preflight {
    /// What a folder holds, counted over it and everything below it.
    public struct Counts: Sendable, Hashable {
        public var created = 0
        public var transfer = 0
        public var metadata = 0
        public var deleted = 0
        public var other = 0
        /// Bytes of created and transferred files.
        public var bytes = 0

        public init() {}

        public var total: Int {
            created + transfer + metadata + deleted + other
        }

        public mutating func add(
            _ item: Item
        ) {
            switch item.kind {
            case .created: created += 1
            case .transfer: transfer += 1
            case .metadata: metadata += 1
            case .deleted: deleted += 1
            case .other: other += 1
            }
            if item.kind == .created || item.kind == .transfer {
                bytes += item.size ?? 0
            }
        }

        public mutating func add(
            _ counts: Counts
        ) {
            created += counts.created
            transfer += counts.transfer
            metadata += counts.metadata
            deleted += counts.deleted
            other += counts.other
            bytes += counts.bytes
        }
    }

    /// One row of the preflight tree: a path rsync touches, a folder above
    /// such paths, or the destination of one rsync command.
    public struct Entry: Sendable, Hashable {
        /// The row's name: one path component, or several joined with `/`
        /// when folders with a single child are collapsed.
        public var name: String
        /// Unique within the tree; the command index, then the path.
        public var id: String
        /// The item at exactly this path, if rsync itemized it.
        public var item: Item?
        public var isFolder: Bool
        /// Over this row and everything below it.
        public var counts: Counts
        /// Children were folded away to fit a line budget; `counts` still covers them.
        public var isFolded = false

        /// A leaf from its item; a folder from what it holds.
        public var change: TreeChangeKind {
            if let item, !isFolder || counts.total == 1 {
                switch item.kind {
                case .created: return .added
                case .deleted: return .removed
                default: return .modified
                }
            }
            if counts.total > 0, counts.created == counts.total {
                return .added
            }
            if counts.total > 0, counts.deleted == counts.total {
                return .removed
            }
            return counts.total == 0 ? .unchanged : .modified
        }
    }

    /// The items as a tree of their paths: shared roots merge, folders with
    /// one child and no item of their own collapse into one row, folders sort
    /// before files. Ignored items are not part of it.
    public static func tree(
        _ items: [Item],
        scope: String = ""
    ) -> Tree<Entry> {
        let root = Builder()
        for item in items {
            let components = item.treePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
                .filter { $0 != "." }
            guard !components.isEmpty else {
                continue
            }
            root.insert(item, components: components[...])
        }
        return Tree(roots: root.nodes(scope: scope, parent: ""))
    }

    /// Keeps the first rows breadth first, expanding a folder only while its
    /// children still fit in `lines`; folders that don't fit are folded.
    public static func folded(
        _ tree: Tree<Entry>,
        lines budget: Int
    ) -> Tree<Entry> {
        var used = tree.roots.count
        var expanded: Set<String> = []
        var level = tree.roots
        while !level.isEmpty {
            var next: [Tree<Entry>.Node] = []
            for node in level where !node.children.isEmpty {
                guard used + node.children.count <= budget else {
                    continue
                }
                used += node.children.count
                expanded.insert(node.value.id)
                next += node.children
            }
            level = next
        }

        func fold(
            _ node: Tree<Entry>.Node
        ) -> Tree<Entry>.Node {
            var node = node
            if expanded.contains(node.value.id) {
                node.children = node.children.map(fold)
            } else if !node.children.isEmpty {
                node.children = []
                node.value.isFolded = true
            }
            return node
        }
        return Tree(roots: tree.roots.map(fold))
    }

    public static func difference(
        _ tree: Tree<Entry>
    ) -> TreeDifference<Entry> {
        func convert(
            _ node: Tree<Entry>.Node
        ) -> Tree<TreeDifference<Entry>.Entry>.Node {
            .init(
                .init(
                    id: node.value.id,
                    label: node.value.name,
                    change: node.value.change,
                    before: nil,
                    after: node.value
                ),
                children: node.children.map(convert)
            )
        }
        return .init(tree: .init(roots: tree.roots.map(convert)), source: .planned)
    }

    private final class Builder {
        var item: Item?
        var isFolder = false
        var children: [String: Builder] = [:]
        var order: [String] = []

        func insert(
            _ item: Item,
            components: ArraySlice<String>
        ) {
            guard let first = components.first else {
                self.item = item
                if item.fileKind == .dir || item.treePath.hasSuffix("/") {
                    isFolder = true
                }
                return
            }
            isFolder = true
            let child: Builder
            if let existing = children[first] {
                child = existing
            } else {
                child = Builder()
                children[first] = child
                order.append(first)
            }
            child.insert(item, components: components.dropFirst())
        }

        func nodes(
            scope: String,
            parent: String
        ) -> [Tree<Entry>.Node] {
            order
                .map { name in (name, children[name]!) }
                .sorted { lhs, rhs in
                    if lhs.1.isFolder != rhs.1.isFolder {
                        return lhs.1.isFolder
                    }
                    return lhs.0 < rhs.0
                }
                .map { name, child in child.node(name: name, scope: scope, parent: parent) }
        }

        func node(
            name: String,
            scope: String,
            parent: String
        ) -> Tree<Entry>.Node {
            var name = name
            var current = self
            while current.item == nil,
                  current.order.count == 1,
                  let only = current.children[current.order[0]],
                  only.isFolder {
                name += "/" + current.order[0]
                current = only
            }
            let path = parent.isEmpty ? name : parent + "/" + name
            let children = current.nodes(scope: scope, parent: path)
            var counts = Counts()
            if let item = current.item {
                counts.add(item)
            }
            for child in children {
                counts.add(child.value.counts)
            }
            return .init(
                Entry(
                    name: name,
                    id: scope.isEmpty ? path : scope + ":" + path,
                    item: current.item,
                    isFolder: current.isFolder,
                    counts: counts
                ),
                children: children
            )
        }
    }
}

extension Sync.Preflight.Item {
    /// The path without a symlink's ` -> target`.
    public var treePath: String {
        guard fileKind == .symlink,
              let arrow = path.range(of: " -> ") else {
            return path
        }
        return String(path[..<arrow.lowerBound])
    }

    /// A symlink's target, from rsync's `%L`.
    public var linkTarget: String? {
        guard fileKind == .symlink,
              let arrow = path.range(of: " -> ") else {
            return nil
        }
        return String(path[arrow.upperBound...])
    }
}

extension Sync.Preflight.Report {
    /// One tree for a single command; with several, one root per command,
    /// named after its destination.
    public func tree() -> Tree<Sync.Preflight.Entry> {
        guard commands.count > 1 else {
            return Sync.Preflight.tree(summary.items)
        }
        return Tree(roots: commands.map { report in
            let children = Sync.Preflight.tree(report.items, scope: "\(report.index)").roots
            var counts = Sync.Preflight.Counts()
            for child in children {
                counts.add(child.value.counts)
            }
            return .init(
                Sync.Preflight.Entry(
                    name: report.command.arguments.last ?? "command \(report.index + 1)",
                    id: "\(report.index)",
                    item: nil,
                    isFolder: true,
                    counts: counts
                ),
                children: children
            )
        })
    }
}
