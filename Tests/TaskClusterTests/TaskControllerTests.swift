import Foundation
import Smockable
import Testing
import WireMVCTesting

@testable import TaskClusterApp
@testable import TaskClusterModel

// The controller suite, served by the app itself.
//
// `@Suite(.wiremvc(.inProcess))` stands up the **real** application: `AppBootstrap.prepare()`, the real
// graph, the real `createRouteBuilder`, the collated route contributors, the global middleware wrap and the
// `@NotFound` fallback — the same build the generated `@main` runs, with the transport swapped. `.inProcess`
// means no socket and no port: the finalized handler is called directly, which covers everything that does
// not depend on the wire.
//
// This replaced a hand-built `TestGraph` that conformed to `WireMVCComposable` around a single contributor.
// That graph could only ever exercise registration; it had no error tiers, no fallback and no composition
// root, so a bug in any of them was invisible here. The trade is that per-test mocks now go through the
// `@Replaces` forwarder in `MockTaskRepository.swift` rather than being constructor-injected per test.
//
// **`.serialized` is load-bearing** — see `withRepository(_:)`.
//
// The keyed `@BindType` harness would remove the need for both the forwarder and `.serialized`, and it is
// what a `@Controller`-based app would use. It does not apply here: swift-wire generates the variant graph
// and doubles struct for this key perfectly well, but wire-mvc emits the keyed suite factory and
// `withClient(supplying:)` only for subjects its `ControllerFinder` matched — `@Controller` declarations —
// and `TaskController` is an `@OpenAPIController`, which wire-open-api contributes with no variant witness.
@Suite("TaskController Tests", .wiremvc(.inProcess), .serialized)
struct TaskControllerTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private static func makeTask(
        taskId: UUID = UUID(),
        title: String = "Test Task",
        priority: Int = 1,
        status: TaskStatus = .pending
    ) -> TaskItem {
        TaskItem(
            taskId: taskId,
            title: title,
            priority: priority,
            status: status,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    @Test("Creating a task with valid input returns 201")
    func createTaskSuccess() async throws {
        let task = Self.makeTask()

        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.create(task: .any), return: task)
        let mock = MockTestTaskRepository(expectations: expectations)

        try await withRepository(mock) {
            try await withClient { client in
                let response = try await client.post("/task", json: CreateTaskBody(title: "Test Task", priority: 1))
                #expect(response.status == 201)
            }
        }
    }

    /// The other side of the same document constraint. Before the range moved into the spec, `createTask`
    /// checked it itself and this case had no test; now it is the *same* generated validator that
    /// `updateTaskPriority` below exercises, reached through a different operation — so what is worth
    /// asserting is that the two agree, and that neither reaches the repository to find out.
    @Test("Creating a task with out-of-range priority returns 400 without touching the repository")
    func createTaskBadRequest() async throws {
        let expectations = MockTestTaskRepository.Expectations()
        let mock = MockTestTaskRepository(expectations: expectations)

        try await withRepository(mock) {
            try await withClient { client in
                let response = try await client.post("/task", json: CreateTaskBody(title: "Test Task", priority: 0))
                #expect(response.status == 400)
            }
        }

        verify(mock, .never).create(task: .any)
    }

    @Test("Getting a non-existent task returns 404")
    func getTaskNotFound() async throws {
        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: nil)
        let mock = MockTestTaskRepository(expectations: expectations)

        try await withRepository(mock) {
            try await withClient { client in
                let response = try await client.get("/task/\(UUID())")
                #expect(response.status == 404)
            }
        }
    }

    @Test("Updating priority with out-of-range value returns 400 without touching the repository")
    func updatePriorityBadRequest() async throws {
        let expectations = MockTestTaskRepository.Expectations()
        let mock = MockTestTaskRepository(expectations: expectations)

        try await withRepository(mock) {
            try await withClient { client in
                let response = try await client.patch("/task/\(UUID())/priority", json: PriorityBody(priority: 99))
                #expect(response.status == 400)
            }
        }

        verify(mock, .never).get(taskId: .any)
        verify(mock, .never).update(task: .any)
    }

    @Test("Cancelling a completed task returns 409")
    func cancelCompletedTaskConflict() async throws {
        let task = Self.makeTask(status: .completed)

        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: task)
        let mock = MockTestTaskRepository(expectations: expectations)

        try await withRepository(mock) {
            try await withClient { client in
                let response = try await client.send("POST", "/task/\(task.taskId)/cancel")
                #expect(response.status == 409)
            }
        }

        verify(mock, .never).update(task: .any)
    }

    @Test("Cancelling a pending task succeeds and sets status to cancelled")
    func cancelPendingTaskSuccess() async throws {
        let task = Self.makeTask(status: .pending)
        var cancelledTask = task
        cancelledTask.status = .cancelled

        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: task)
        when(expectations.update(task: .any), return: cancelledTask)
        let mock = MockTestTaskRepository(expectations: expectations)

        try await withRepository(mock) {
            try await withClient { client in
                let response = try await client.send(
                    "POST",
                    "/task/\(task.taskId)/cancel",
                    headers: ["Accept": "application/json"]
                )
                #expect(response.status == 200)
                #expect(try response.json(TaskResponseBody.self).status == "cancelled")
            }
        }

        verify(mock).update(task: .matching { $0.status == .cancelled })
    }

    /// The health route — an annotation-driven `@Get` beside four document-driven operations, on the one
    /// router. It has a generated typed client because it *is* a `@Controller`, which is the same
    /// distinction that keeps `TaskController` off the keyed harness.
    @Test("The health route serves 200")
    func healthIsServed() async throws {
        try await withClient(for: HealthControllerClient.self) { health in
            try await health.health()
        }
    }

    /// The `@NotFound` fallback the composition root declares. Unreachable from the old hand-built graph —
    /// there was no fallback in it to reach.
    @Test("An unmatched path reaches the composition root's @NotFound handler")
    func unmatchedPathReachesFallback() async throws {
        try await withClient { client in
            let response = try await client.get("/no-such-route")
            #expect(response.status == 404)
        }
    }
}

private struct CreateTaskBody: Encodable {
    var title: String
    var priority: Int
}

private struct PriorityBody: Encodable {
    var priority: Int
}

private struct TaskResponseBody: Decodable {
    var status: String
}
