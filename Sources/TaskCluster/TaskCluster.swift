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

        // Controllers collate into the graph's `WireMVCComposable` surface as **route contributors** —
        // an OpenAPI operation is a WireMVC route since M6d, so it collates the same way a `@Get` would.
        // `WireMVCServerTransport` bridges them onto Hummingbird's `Router`, and serves the graph's
        // wiring model on the same router.
        let application = try buildApplication(
            graph: graph,
            configuration: configuration,
            logger: graph.logger
        )
        try await application.run()
    }
}
