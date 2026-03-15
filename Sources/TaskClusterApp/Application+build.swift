import Hummingbird
import Logging
import OpenAPIHummingbird
import OpenAPIRuntime
import TaskClusterModel

package func buildApplication<Repository: TaskRepository>(
    repository: Repository,
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

    let controller = TaskController(repository: repository)
    try controller.registerHandlers(on: router)

    return Application(router: router, configuration: configuration, logger: logger)
}
