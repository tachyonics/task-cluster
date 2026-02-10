import Foundation
import Hummingbird
import Logging
import OpenAPIHummingbird
import OpenAPIRuntime
import TaskClusterModel

public typealias AppRequestContext = BasicRequestContext

public func buildApplication(
    repository: some TaskRepository,
    configuration: ApplicationConfiguration = .init(address: .hostname("127.0.0.1", port: 8080)),
    logger: Logger = Logger(label: "task-cluster")
) throws -> some ApplicationProtocol {
    let router = try buildRouter(repository: repository)
    return Application(
        router: router,
        configuration: configuration,
        logger: logger
    )
}

func buildRouter(repository: some TaskRepository) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)

    router.addMiddleware {
        LogRequestsMiddleware(.info)
    }

    router.get("/") { _, _ in
        "task-cluster is running"
    }

    let taskController = TaskController(repository: repository)
    try taskController.registerHandlers(on: router)

    return router
}
