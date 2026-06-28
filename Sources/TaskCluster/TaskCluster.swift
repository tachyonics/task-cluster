import Configuration
import Hummingbird
import TaskClusterApp

@main
struct TaskCluster {
    static func main() async throws {
        let graph = try await _WireGraph.bootstrap()
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        let port = config.int(forKey: "HTTP_PORT", default: 8080)

        let configuration = ApplicationConfiguration(
            address: .hostname("0.0.0.0", port: port)
        )

        let application = try buildApplication(
            controller: graph.compositionRoot.controller,
            configuration: configuration,
            logger: graph.logger
        )
        try await application.run()
    }
}
