import Configuration
import DynamoDBTables
import Hummingbird
import Logging
import TaskClusterApp
import TaskClusterDynamoDBModel

@main
struct TaskCluster {
    static func main() async throws {
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        let port = config.int(forKey: "HTTP_PORT", default: 8080)

        let logger = Logger(label: "TaskCluster")
        let table = InMemoryDynamoDBCompositePrimaryKeyTable()
        let repository = DynamoDBTaskRepository(table: table)
        let configuration = ApplicationConfiguration(
            address: .hostname("0.0.0.0", port: port)
        )

        let application = try buildApplication(
            repository: repository,
            configuration: configuration,
            logger: logger
        )
        try await application.run()
    }
}
