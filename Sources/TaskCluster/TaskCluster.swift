import Configuration
import Hummingbird
import TaskClusterApp

@main
struct TaskCluster {
    static func main() async throws {
        let graph = try await Wire.bootstrap()
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        let port = config.int(forKey: "HTTP_PORT", default: 8080)

        let configuration = ApplicationConfiguration(
            address: .hostname("0.0.0.0", port: port)
        )

        // Controllers collate into the graph's `TransportComposable` surface; the
        // adapter registers each onto the router's `ServerTransport`.
        let application = try buildApplication(
            graph: graph,
            configuration: configuration,
            logger: graph.logger
        )
        try await application.run()
    }
}
