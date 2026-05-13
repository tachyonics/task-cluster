import AsyncHTTPClient
import ContainerMacrosLib
import ContainerTestSupport
import Foundation
import NIOCore
import Testing

/// Cross-container integration test — proves the env-injection path
/// end-to-end. Wires:
///   1. A LocalStack container running the `TaskClusterDDBStack`
///      stack (codegen'd at build time from
///      `Resources/dynamodb-table.json`, generates a `DynamodbTableOutputs`
///      typed view of `tableName`).
///   2. The TaskCluster service container, built from the package-root
///      Dockerfile, with environment closure injecting the DDB endpoint
///      + table name from sibling outputs.
///
/// Round-trips a task POST/GET — persistence flows through real
/// LocalStack DDB this time, not the in-memory fallback the simpler
/// `TaskClusterIntegrationTests` exercises.
@Containers
struct TaskClusterWithDDBContainers {
    @LocalStackContainer(stackName: "TaskClusterDDBStack")
    var aws: DynamodbTableOutputs

    @DockerfileContainer(
        waitStrategy: .httpGet(path: "/health"),
        containerLogLevel: .info,
        environment: { (containers: TaskClusterWithDDBContainers) in
            [
                "TASK_TABLE_NAME": containers.aws.tableName,
                "AWS_ENDPOINT_URL": containers.aws.awsEndpoint,
                "AWS_REGION": "us-east-1",
                "AWS_ACCESS_KEY_ID": "test",
                "AWS_SECRET_ACCESS_KEY": "test",
            ]
        }
    )
    var taskCluster: ServiceEndpoint
}

@Suite(
    TaskClusterWithDDBContainers.containerTrait,
    .tags(.integration, .docker, .localstack),
    .enabled(if: containerRuntimeAvailable, "Container runtime is required"),
    .enabled(
        if: localStackAuthTokenAvailable,
        "LOCALSTACK_AUTH_TOKEN is required (set it in the environment or in .local-containers/env)"
    )
)
struct TaskClusterLocalStackIntegrationTests {
    let containers = TaskClusterWithDDBContainers()

    @Test("Task created via the service persists through real LocalStack DynamoDB")
    func roundTripThroughLocalStackDDB() async throws {
        let baseURL = containers.taskCluster.baseURL

        var createRequest = HTTPClientRequest(url: "\(baseURL)/task")
        createRequest.method = .POST
        createRequest.headers.add(name: "content-type", value: "application/json")
        createRequest.body = .bytes(
            Data(#"{"title":"persisted to ddb","priority":2}"#.utf8)
        )

        let createResponse = try await HTTPClient.shared.execute(
            createRequest,
            timeout: .seconds(15)
        )
        #expect(createResponse.status == .created)

        let createdBody = try await createResponse.body.collect(upTo: 1024 * 1024)
        let created = try JSONDecoder.iso8601.decode(WireTask.self, from: createdBody)

        var getRequest = HTTPClientRequest(url: "\(baseURL)/task/\(created.taskId)")
        getRequest.method = .GET
        let getResponse = try await HTTPClient.shared.execute(
            getRequest,
            timeout: .seconds(15)
        )
        #expect(getResponse.status == .ok)

        let fetchedBody = try await getResponse.body.collect(upTo: 1024 * 1024)
        let fetched = try JSONDecoder.iso8601.decode(WireTask.self, from: fetchedBody)
        #expect(fetched.taskId == created.taskId)
        #expect(fetched.title == "persisted to ddb")
        #expect(fetched.priority == 2)
        #expect(fetched.status == "pending")
    }
}

private struct WireTask: Codable {
    let taskId: UUID
    let title: String
    let priority: Int
    let status: String
    let createdAt: Date
    let updatedAt: Date
}

extension JSONDecoder {
    fileprivate static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
