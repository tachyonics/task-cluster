import Configuration
import Hummingbird
import TaskClusterApp

@main
struct TaskCluster {
    static func main() async throws {
        let graph = try await _Wire.bootstrap()
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        let port = config.int(forKey: "HTTP_PORT", default: 8080)

        let configuration = ApplicationConfiguration(
            address: .hostname("0.0.0.0", port: port)
        )

        // The controller is a graph node under its structural identity
        // (`TaskController<some TaskRepository>`) — read it directly and hand it
        // to the framework, which takes it as `some APIProtocol`.
        let application = try buildApplication(
            controller: graph.taskControllerOfSomeTaskRepository,
            configuration: configuration,
            logger: graph.logger
        )
        try await application.run()
    }
}
