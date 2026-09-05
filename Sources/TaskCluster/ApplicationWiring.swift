import Configuration
import DynamoDBTables
import DynamoDBTablesSoto
import SotoCore
import SotoDynamoDB
import Wire

package enum ApplicationWiring {
    // `ConfigReader` is no longer provided here — it is a graph *input* now, built by
    // `AppBootstrap.prepare()` before any binding exists and handed to `Wire.bootstrap(inputs:)`. The
    // bindings below still `@Inject` it exactly as they did; only where the value comes from changed.
    //
    // The logger binding is gone with it. It existed to be read back off the graph and handed to the
    // Hummingbird `Application`, which no longer exists; `LoggingSystem.bootstrap` runs in the pre-step,
    // so a binding that wants a logger mints its own against the installed handler.

    // The AWS client — a process-lifetime resource with no run loop. Soto rather than aws-sdk-swift
    // because the latter has compile issues against the static-musl SDK the production image builds with.
    //
    // **`@Teardown` does not currently run under the generated entry point.** `WireMVC.serve` never
    // receives the graph, and nothing makes `server.serve` return, so there is no shutdown trigger to
    // reach the walk from — wire-mvc#177, which tracks both halves. The annotation is correct and stays:
    // it is what the graph reads to order the walk, and it is what will fire once that lands. What it
    // means today is that SIGTERM ends the process without draining this client.
    @Provides
    @Teardown({ (client: AWSClient) in try await client.shutdown() })
    package static func awsClient() -> AWSClient { AWSClient() }

    @Provides
    package static func dynamoDB(client: AWSClient, config: ConfigReader) -> SotoDynamoDB.DynamoDB {
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
    package static func table(
        dynamoDB: SotoDynamoDB.DynamoDB,
        config: ConfigReader
    ) -> some DynamoDBCompositePrimaryKeyTable & Sendable {
        SotoDynamoDBCompositePrimaryKeyTable(
            tableName: config.string(forKey: "TASK_TABLE_NAME", default: "tasks"),
            client: dynamoDB
        )
    }
}
