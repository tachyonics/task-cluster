import Hummingbird
import Logging
import OpenAPIHummingbird  // swiftlint:disable:this unused_import
import Wire
import WireHummingbird
import WireOpenAPI

package func buildApplication(
    graph: some TransportComposable & Introspectable & Teardownable & Sendable,
    configuration: ApplicationConfiguration,
    logger: Logger
) throws -> some ApplicationProtocol {
    let router = Router(context: BasicRequestContext.self)

    router.addMiddleware {
        LogRequestsMiddleware(.info)
    }

    router.get("/health") { _, _ in
        HTTPResponse.Status.ok
    }

    // WireHummingbird and WireOpenAPI coexist on one graph: the OpenAPI controllers
    // register their handlers, and the graph's wiring model is served here.
    try WireOpenAPI.apply(graph, to: router)
    WireHummingbird.mountIntrospection(graph, on: router.group("wiring"))

    // Teardown (M4): the graph's `@Teardown` actions (the AWS client `shutdown()`) run at
    // app-scope shutdown via a service that shuts down last — after the server stops.
    return Application(
        router: router,
        configuration: configuration,
        services: [WireHummingbird.teardownService(graph, logger: logger)],
        logger: logger
    )
}
