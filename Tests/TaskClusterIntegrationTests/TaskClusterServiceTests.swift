import AsyncHTTPClient
import ContainerMacrosLib
import ContainerTestSupport
import Foundation
import NIOCore
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

@Suite(
    TaskClusterContainers.containerTrait,
    .tags(.integration),
    .enabled(if: containerRuntimeAvailable, "Container runtime is required")
)
struct TaskClusterIntegrationTests {
    let containers = TaskClusterContainers()

    @Test("Round-trips a task through the running service")
    func createAndGet() async throws {
        let baseURL = containers.taskCluster.baseURL  // e.g. "http://127.0.0.1:54321"

        var createRequest = HTTPClientRequest(url: "\(baseURL)/task")
        createRequest.method = .POST
        createRequest.headers.add(name: "content-type", value: "application/json")
        createRequest.body = .bytes(
            Data(#"{"title":"build the thing","priority":1}"#.utf8)
        )

        let createResponse = try await HTTPClient.shared.execute(
            createRequest,
            timeout: .seconds(10)
        )
        #expect(createResponse.status == .created)

        let createdBody = try await createResponse.body.collect(upTo: 1024 * 1024)
        let created = try JSONDecoder.iso8601.decode(WireTask.self, from: createdBody)

        var getRequest = HTTPClientRequest(url: "\(baseURL)/task/\(created.taskId)")
        getRequest.method = .GET
        let getResponse = try await HTTPClient.shared.execute(
            getRequest,
            timeout: .seconds(10)
        )
        #expect(getResponse.status == .ok)

        let fetchedBody = try await getResponse.body.collect(upTo: 1024 * 1024)
        let fetched = try JSONDecoder.iso8601.decode(WireTask.self, from: fetchedBody)
        #expect(fetched.taskId == created.taskId)
        #expect(fetched.title == "build the thing")
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
