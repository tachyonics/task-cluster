import Foundation
import Hummingbird
import HummingbirdTesting
import NIOFoundationCompat
import Logging
import Smockable
import Testing

@testable import TaskClusterApp
@testable import TaskClusterModel

@Suite("TaskController Tests")
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

        let app = try buildApplication(
            repository: mock,
            configuration: .init(),
            logger: Logger(label: "test")
        )

        try await app.test(.router) { client in
            let body = ByteBuffer(
                string: """
                    {"title":"Test Task","priority":1}
                    """
            )
            try await client.execute(
                uri: "/task",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                #expect(response.status == .created)
            }
        }
    }

    @Test("Getting a non-existent task returns 404")
    func getTaskNotFound() async throws {
        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: nil)
        let mock = MockTestTaskRepository(expectations: expectations)

        let app = try buildApplication(
            repository: mock,
            configuration: .init(),
            logger: Logger(label: "test")
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(UUID())",
                method: .get
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("Updating priority with out-of-range value returns 400 without touching the repository")
    func updatePriorityBadRequest() async throws {
        let expectations = MockTestTaskRepository.Expectations()
        let mock = MockTestTaskRepository(expectations: expectations)

        let app = try buildApplication(
            repository: mock,
            configuration: .init(),
            logger: Logger(label: "test")
        )

        try await app.test(.router) { client in
            let body = ByteBuffer(
                string: """
                    {"priority":99}
                    """
            )
            try await client.execute(
                uri: "/task/\(UUID())/priority",
                method: .patch,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                #expect(response.status == .badRequest)
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

        let app = try buildApplication(
            repository: mock,
            configuration: .init(),
            logger: Logger(label: "test")
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(task.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .conflict)
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

        let app = try buildApplication(
            repository: mock,
            configuration: .init(),
            logger: Logger(label: "test")
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(task.taskId)/cancel",
                method: .post,
                headers: [.accept: "application/json"]
            ) { response in
                #expect(response.status == .ok)

                let responseBody = try JSONDecoder().decode(
                    TaskResponseBody.self,
                    from: Data(buffer: response.body)
                )
                #expect(responseBody.status == "cancelled")
            }
        }

        verify(mock).update(task: .matching { $0.status == .cancelled })
    }
}

private struct TaskResponseBody: Decodable {
    var status: String
}
