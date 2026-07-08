import Configuration
import DynamoDBTables
import DynamoDBTablesSoto
import Logging
import SotoCore
import SotoDynamoDB
import Wire

enum ApplicationWiring {
    // Read off the graph at the composition root and handed to the (non-Wire-managed)
    // Application; nothing in the graph @Injects it, so allowUnused silences the
    // dead-binding warning.
    @Provides(allowUnused: true)
    static let logger = Logger(label: "TaskCluster")

    // Configuration source for the resource chain below. Env-backed: `TASK_TABLE_NAME`,
    // `AWS_REGION`, `AWS_ENDPOINT_URL` (the last pointing at LocalStack in tests).
    @Provides
    static let config = ConfigReader(provider: EnvironmentVariablesProvider())

    // The AWS client — a process-lifetime resource with no run loop. `@Teardown` (M4) is
    // what makes it a real resource: Wire calls `shutdown()` at app-scope teardown, in
    // reverse dependency order, once the server has stopped. Soto rather than
    // aws-sdk-swift because the latter has compile issues against the static-musl SDK the
    // production image builds with.
    @Provides
    @Teardown({ (client: AWSClient) in try await client.shutdown() })
    static func awsClient() -> AWSClient { AWSClient() }

    @Provides
    static func dynamoDB(client: AWSClient, config: ConfigReader) -> SotoDynamoDB.DynamoDB {
        SotoDynamoDB.DynamoDB(
            client: client,
            region: Region(rawValue: config.string(forKey: "AWS_REGION", default: "us-east-1")),
            endpoint: config.string(forKey: "AWS_ENDPOINT_URL")
        )
    }

    // The composition-root leaf: the single concrete table choice, hidden behind an opaque
    // identity so the constrained-parameter chain resolves by identity (`some
    // TaskRepository` for the repo; the controller keeps its real `TaskController<some
    // TaskRepository>`) without spelling the nested concrete stack. The `& Sendable`
    // matches the repository's `Table` constraint.
    @Provides
    static func table(
        dynamoDB: SotoDynamoDB.DynamoDB,
        config: ConfigReader
    ) -> some DynamoDBCompositePrimaryKeyTable & Sendable {
        SotoDynamoDBCompositePrimaryKeyTable(
            tableName: config.string(forKey: "TASK_TABLE_NAME", default: "tasks"),
            client: dynamoDB
        )
    }
}
