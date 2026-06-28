import Hummingbird
import Logging
import OpenAPIHummingbird
import TaskAPI
import TaskClusterModel

package func buildApplication(
    controller: some APIProtocol,
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

    try controller.registerHandlers(on: router)

    return Application(router: router, configuration: configuration, logger: logger)
}
