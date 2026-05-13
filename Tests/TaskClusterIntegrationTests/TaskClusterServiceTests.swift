import ContainerMacrosLib
import ContainerTestSupport
import Foundation
import OpenAPIRuntime
import TaskAPI
import Testing

@Containers
struct TaskClusterContainers {
    /// Builds the image from `Dockerfile` at the package root (the default
    /// `context:` is `"."`, resolved against the nearest enclosing `Package.swift`).
    /// Exposed ports are auto-detected from the built image's metadata and mapped
    /// to dynamic host ports. The trait polls `GET /health` on the resolved host
    /// port until it returns 200 before handing control to the test.
    @DockerfileContainer(
        waitStrategy: .httpGet(path: "/health"),
        containerLogLevel: .info
    )
    var taskCluster: ServiceEndpoint
}

/// Smoke test for the wiring: build → container start → OpenAPI client →
/// in-memory `DynamoDBCompositePrimaryKeyTable` fallback (no LocalStack).
///
/// Persistence-shape coverage and per-endpoint behavior live in
/// `TaskClusterLocalStackIntegrationTests`. This suite exists to catch
/// "service doesn't start" / "OpenAPI contract drifted" regressions without
/// paying the LocalStack startup cost.
@Suite(
    TaskClusterContainers.containerTrait,
    .tags(.integration),
    .enabled(if: containerRuntimeAvailable, "Container runtime is required")
)
struct TaskClusterIntegrationTests {
    let containers = TaskClusterContainers()

    @Test("Round-trips a task through the running service via the OpenAPI client")
    func createAndGet() async throws {
        let client = try makeTaskAPIClient(baseURL: containers.taskCluster.baseURL)

        let createResponse = try await client.createTask(
            body: .json(.init(title: "build the thing", priority: 1))
        )
        let created = try createResponse.created.body.json

        let getResponse = try await client.getTask(path: .init(taskId: created.taskId))
        let fetched = try getResponse.ok.body.json
        #expect(fetched.taskId == created.taskId)
        #expect(fetched.title == "build the thing")
        #expect(fetched.status == .pending)
    }
}
