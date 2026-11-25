import Arguments

/// `syncer plan <route>` or `syncer plan --all`.
struct PlanOptions: Sendable, ArgumentParsed {
    typealias ArgumentPayload = Payload

    enum Selection: Sendable {
        case all
        case route(String)
    }

    let selection: Selection

    init(
        arguments: Payload
    ) throws {
        if arguments.all {
            selection = .all
        } else {
            guard !arguments.route.isEmpty else {
                throw SyncerCLIError.planNeedsRoute
            }
            selection = .route(arguments.route)
        }
    }

    struct Payload: ArgumentGroup {
        @Arg("route", help: "Route name or alias. Omit with --all.", default: "")
        var route: String

        @Flag("all", help: "Every route.")
        var all: Bool

        init() {}
    }
}
