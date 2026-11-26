import Primitives
import Syncer
import TestFlows

/// The preflight item list as a tree (`Sync.Preflight.tree`, `folded`).
enum PreflightTreeFlows {
    static func items(
        _ lines: [String]
    ) throws -> [Sync.Preflight.Item] {
        try lines.map { line in
            guard let item = Sync.Preflight.Item(line) else {
                throw TestFlowAssertionFailure(label: "item", message: "not an itemized line: \(line)")
            }
            return item
        }
    }

    static func names(
        _ nodes: [Tree<Sync.Preflight.Entry>.Node]
    ) -> [String] {
        nodes.map(\.value.name)
    }

    static let sample = [
        "cd+++++++++\t4096\tsite/",
        ">f+++++++++\t100\tsite/app/new.txt",
        ">f.st......\t250\tsite/app/lib/deep/changed.swift",
        ".f..t......\t10\tsite/app/lib/deep/touched.swift",
        "*deleting   site/old/gone.txt",
        ">f.st......\t5\tsite/readme.md",
    ]

    static let flows: [TestFlow] = [
        TestFlow("preflight-tree-shape", tags: ["preflight", "tree"]) {
            let tree = Sync.Preflight.tree(try items(sample))
            try Expect.equal(names(tree.roots), ["site"], "one root for the shared prefix")

            let site = tree.roots[0]
            try Expect.true(site.value.isFolder, "a folder")
            try Expect.equal(site.value.change, .modified, "mixed changes below")
            try Expect.equal(names(site.children), ["app", "old", "readme.md"], "folders first, then files")

            let app = site.children[0]
            try Expect.equal(names(app.children), ["lib/deep", "new.txt"], "a single-child chain collapses")
            try Expect.equal(app.children[0].value.id, "site/app/lib/deep", "id keeps the full path")

            let counts = site.value.counts
            try Expect.equal(counts.created, 2, "created folder and file")
            try Expect.equal(counts.transfer, 2, "two transfers")
            try Expect.equal(counts.deleted, 1, "one deletion")
            try Expect.equal(counts.bytes, 4096 + 100 + 250 + 5, "bytes of created and transferred items")

            try Expect.equal(site.children[1].value.change, .removed, "a folder holding only deletions")
            return []
        },

        TestFlow("preflight-tree-folding", tags: ["preflight", "tree"]) {
            let tree = Sync.Preflight.tree(try items(sample))
            let folded = Sync.Preflight.folded(tree, lines: 4)
            let site = folded.roots[0]
            try Expect.equal(names(site.children), ["app", "old", "readme.md"], "the first level fits")
            try Expect.true(site.children[0].children.isEmpty, "app folded")
            try Expect.true(site.children[0].value.isFolded, "marked folded")
            try Expect.equal(site.children[0].value.counts.total, 3, "a folded folder keeps its counts")

            let full = Sync.Preflight.folded(tree, lines: 1000)
            try Expect.false(full.roots[0].children[0].value.isFolded, "a large budget folds nothing")
            return []
        },

        TestFlow("preflight-tree-symlink", tags: ["preflight", "tree"]) {
            let tree = Sync.Preflight.tree(try items(["cL+++++++++\t0\tbin/tool -> ../lib/tool"]))
            let link = tree.roots[0].children[0].value
            try Expect.equal(link.name, "tool", "the link name, without its target")
            try Expect.equal(link.item?.linkTarget, "../lib/tool", "the target stays on the item")
            return []
        },
    ]
}
