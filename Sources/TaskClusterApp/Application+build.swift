import Hummingbird
import Logging
// Conformance-only import: `extension Router: ServerTransport`, which `WireMVCServerTransport.apply`
// needs but no symbol here names.
import OpenAPIHummingbird  // swiftlint:disable:this unused_import
import Wire
import WireMVC
import WireMVCServerTransport

package func buildApplication(
    graph: some WireMVCComposable & Introspectable & Teardownable & Sendable,
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

    // One collation surface. `WireOpenAPI.apply` is gone — it retired with `TransportKeys.handlers`
    // when operations became WireMVC routes — so the OpenAPI controllers arrive through the same
    // `WireMVCServerTransport.apply` that would carry any `@Get` route, bridged onto Hummingbird's
    // `Router` as a `ServerTransport`. Nothing here names OpenAPI: the adapter registers every collated
    // contributor, so adding annotation-driven routes to this app would need no change at this line.
    //
    // It returns the graph's collated app-scoped services; this app has none today, so they are dropped
    // rather than threaded into `Application(services:)` — the AWS client is a `@Teardown` resource, not
    // a run loop, and is handled by the teardown service below.
    _ = try WireMVCServerTransport.apply(graph, to: router)
    try WireMVCServerTransport.mountIntrospection(for: graph, on: router, at: "/wiring")

    // Teardown (M4): the graph's `@Teardown` actions (the AWS client `shutdown()`) run at
    // app-scope shutdown via a service that shuts down last — after the server stops.
    return Application(
        router: router,
        configuration: configuration,
        services: [GraphTeardownService(graph: graph, logger: logger)],
        logger: logger
    )
}
