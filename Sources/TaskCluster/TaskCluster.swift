import Configuration
import DynamoDBTables
import DynamoDBTablesSoto
import Hummingbird
import Logging
import SotoCore
import SotoDynamoDB
import TaskClusterApp
import TaskClusterDynamoDBModel
import TaskClusterModel

@main
struct TaskCluster {
    static func main() async throws {
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        let port = config.int(forKey: "HTTP_PORT", default: 8080)
        let tableName = config.string(forKey: "TASK_TABLE_NAME")

        let logger = Logger(label: "TaskCluster")
        let configuration = ApplicationConfiguration(
            address: .hostname("0.0.0.0", port: port)
        )

        // When `TASK_TABLE_NAME` is set we expect a real DynamoDB table — either
        // a LocalStack one (with `AWS_ENDPOINT_URL` pointing at it) for tests, or
        // the production one in the deployed VPC. When unset, fall back to the
        // in-memory store for local-dev iteration.
        //
        // Soto (rather than aws-sdk-swift) is used because aws-sdk-swift
        // currently has compile issues against the static-Linux-musl SDK that
        // the production Dockerfile builds with.
        if let tableName {
            let region = config.string(forKey: "AWS_REGION", default: "us-east-1")
            let endpoint = config.string(forKey: "AWS_ENDPOINT_URL")
            let awsClient = AWSClient()
            let dynamoDB = SotoDynamoDB.DynamoDB(
                client: awsClient,
                region: Region(rawValue: region),
                endpoint: endpoint
            )
            let table = SotoDynamoDBCompositePrimaryKeyTable(
                tableName: tableName,
                client: dynamoDB
            )
            try await runApp(
                repository: DynamoDBTaskRepository(table: table),
                configuration: configuration,
                logger: logger
            )
            try await awsClient.shutdown()
        } else {
            let table = InMemoryDynamoDBCompositePrimaryKeyTable()
            try await runApp(
                repository: DynamoDBTaskRepository(table: table),
                configuration: configuration,
                logger: logger
            )
        }
    }

    private static func runApp<Repository: TaskRepository>(
        repository: Repository,
        configuration: ApplicationConfiguration,
        logger: Logger
    ) async throws {
        let application = try buildApplication(
            repository: repository,
            configuration: configuration,
            logger: logger
        )
        try await application.run()
    }
}
