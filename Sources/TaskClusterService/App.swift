import Configuration
import Hummingbird
import TaskClusterApp
import TaskClusterModel

@main
struct App {
    static func main() async throws {
        let reader = try await ConfigReader(providers: [
            CommandLineArgumentsProvider(),
            EnvironmentVariablesProvider(),
            EnvironmentVariablesProvider(environmentFilePath: ".env", allowMissing: true),
            InMemoryProvider(values: [
                "http.serverName": "task-cluster",
            ]),
        ])

        let repository = InMemoryTaskRepository()
        let app = try buildApplication(
            repository: repository,
            configuration: .init(reader: reader.scoped(to: "http"))
        )
        try await app.runService()
    }
}
