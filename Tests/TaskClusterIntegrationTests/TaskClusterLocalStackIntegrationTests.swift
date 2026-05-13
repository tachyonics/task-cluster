import ContainerMacrosLib
import ContainerTestSupport
import DynamoDBTablesSoto
import Foundation
import TaskAPI
import TaskClusterModel
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
/// Tests in this suite drive the service via the OpenAPI-generated client
/// (so the API contract is type-checked against `openapi.yaml`) and verify
/// effects by reading DynamoDB directly via `DynamoDBTables` (so the
/// persistence-shape assertion is independent of the service code under
/// test). Pure controller-routing concerns — invalid UUIDs, malformed JSON,
/// no-state 404s — are not duplicated here; they live in the in-process
/// `TaskControllerTests` against a `MockTaskRepository`.
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

    // MARK: - createTask

    @Test("createTask persists a pending row with the requested attributes")
    func createPersistsPendingRow() async throws {
        let (client, table, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let response = try await client.createTask(
            body: .json(.init(title: "persisted to ddb", priority: 2))
        )
        let created = try response.created.body.json
        let createdId = try #require(UUID(uuidString: created.taskId))

        let row = try #require(try await readTask(createdId, from: table))
        #expect(row.taskId == createdId)
        #expect(row.title == "persisted to ddb")
        #expect(row.priority == 2)
        #expect(row.status == .pending)
        // Timestamps are server-assigned; just confirm they're populated and
        // that createdAt == updatedAt for a freshly-created row.
        #expect(row.createdAt == row.updatedAt)
    }

    // MARK: - getTask

    @Test("getTask returns a row that was seeded directly into the table")
    func getReturnsSeededRow() async throws {
        let (client, table, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let seeded = TaskItem(
            taskId: UUID(),
            title: "seeded from test",
            description: "directly inserted, never went through the service",
            priority: 3,
            status: .running
        )
        try await seedTask(seeded, into: table)

        let response = try await client.getTask(path: .init(taskId: seeded.taskId.uuidString))
        let fetched = try response.ok.body.json

        #expect(fetched.taskId == seeded.taskId.uuidString)
        #expect(fetched.title == "seeded from test")
        #expect(fetched.description == "directly inserted, never went through the service")
        #expect(fetched.priority == 3)
        #expect(fetched.status == .running)
    }

    // MARK: - updateTaskPriority

    @Test("updateTaskPriority mutates the row and advances updatedAt")
    func updatePriorityMutatesRow() async throws {
        let (client, table, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let originalUpdatedAt = Date(timeIntervalSince1970: 1_000_000)
        let seeded = TaskItem(
            taskId: UUID(),
            title: "priority bump candidate",
            priority: 1,
            createdAt: originalUpdatedAt,
            updatedAt: originalUpdatedAt
        )
        try await seedTask(seeded, into: table)

        _ = try await client.updateTaskPriority(
            path: .init(taskId: seeded.taskId.uuidString),
            body: .json(.init(priority: 5))
        ).ok

        let row = try #require(try await readTask(seeded.taskId, from: table))
        #expect(row.priority == 5)
        #expect(row.updatedAt > originalUpdatedAt)
        #expect(row.createdAt == originalUpdatedAt)  // createdAt must not move
    }

    @Test("updateTaskPriority returns 400 for invalid priority and leaves the row unchanged")
    func updatePriorityInvalidLeavesRowUnchanged() async throws {
        let (client, table, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let seeded = TaskItem(
            taskId: UUID(),
            title: "validation guard test",
            priority: 4
        )
        try await seedTask(seeded, into: table)
        // Read back the seeded row as the baseline. DDB's ISO 8601 timestamp
        // representation has lower precision than `Date()`, so comparing the
        // post-action row against the in-memory `seeded` value would fail on
        // timestamps even when nothing actually changed. Baseline-vs-after
        // comparison uses the same precision on both sides.
        let baseline = try #require(try await readTask(seeded.taskId, from: table))

        let response = try await client.updateTaskPriority(
            path: .init(taskId: seeded.taskId.uuidString),
            body: .json(.init(priority: -1))  // outside 1...10 range
        )
        if case .badRequest = response {
            // expected
        } else {
            Issue.record("Expected .badRequest, got \(response)")
        }

        // Crucially: the row in DDB is byte-for-byte the baseline. A
        // regression where the controller validated *after* writing would
        // pass a mock-based unit test but fail this assertion.
        let row = try #require(try await readTask(seeded.taskId, from: table))
        #expect(row == baseline)
    }

    @Test("updateTaskPriority returns 404 when the task does not exist")
    func updatePriorityMissingReturns404() async throws {
        let (client, _, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let response = try await client.updateTaskPriority(
            path: .init(taskId: UUID().uuidString),
            body: .json(.init(priority: 5))
        )
        if case .notFound = response {
            // expected
        } else {
            Issue.record("Expected .notFound, got \(response)")
        }
    }

    // MARK: - cancelTask

    @Test("cancelTask sets status to cancelled and advances updatedAt")
    func cancelMarksRowCancelled() async throws {
        let (client, table, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let originalUpdatedAt = Date(timeIntervalSince1970: 1_000_000)
        let seeded = TaskItem(
            taskId: UUID(),
            title: "to be cancelled",
            priority: 2,
            status: .pending,
            createdAt: originalUpdatedAt,
            updatedAt: originalUpdatedAt
        )
        try await seedTask(seeded, into: table)

        _ = try await client.cancelTask(
            path: .init(taskId: seeded.taskId.uuidString)
        ).ok

        let row = try #require(try await readTask(seeded.taskId, from: table))
        #expect(row.status == .cancelled)
        #expect(row.updatedAt > originalUpdatedAt)
        #expect(row.createdAt == originalUpdatedAt)
    }

    @Test("cancelTask returns 409 for a completed task and leaves the row unchanged")
    func cancelCompletedReturns409() async throws {
        let (client, table, shutdown) = try await harness()
        defer { Task { try? await shutdown() } }

        let seeded = TaskItem(
            taskId: UUID(),
            title: "already done",
            priority: 1,
            status: .completed
        )
        try await seedTask(seeded, into: table)
        // Baseline read at storage-precision (see updatePriorityInvalid…).
        let baseline = try #require(try await readTask(seeded.taskId, from: table))

        let response = try await client.cancelTask(
            path: .init(taskId: seeded.taskId.uuidString)
        )
        if case .conflict = response {
            // expected
        } else {
            Issue.record("Expected .conflict, got \(response)")
        }

        let row = try #require(try await readTask(seeded.taskId, from: table))
        #expect(row == baseline)  // no partial write on the rejected path
    }

    // MARK: - Test harness

    /// Builds an OpenAPI client + a directly-pointed table for the running
    /// containers, plus a shutdown closure the caller defers to clean up
    /// the underlying `AWSClient`.
    private func harness() async throws -> (
        client: Client,
        table: SotoDynamoDBCompositePrimaryKeyTable,
        shutdown: @Sendable () async throws -> Void
    ) {
        let client = try makeTaskAPIClient(baseURL: containers.taskCluster.baseURL)
        let (table, shutdown) = makeTaskTable(
            endpoint: containers.aws.awsEndpoint,
            tableName: containers.aws.tableName
        )
        return (client, table, shutdown)
    }
}
