import Hummingbird
import Logging
import OpenAPIHummingbird  // swiftlint:disable:this unused_import
import WireOpenAPI

package func buildApplication(
    graph: some TransportComposable,
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

    try WireOpenAPI.apply(graph, to: router)

    return Application(router: router, configuration: configuration, logger: logger)
}
