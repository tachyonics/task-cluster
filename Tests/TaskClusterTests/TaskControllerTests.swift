import Foundation
import Hummingbird
import HummingbirdTesting
import Smockable
import TaskClusterApp
import TaskClusterModel
import Testing

@Smock
protocol TestTaskRepository: TaskRepository {
    func create(task: TaskItem) async throws -> TaskItem
    func get(taskId: UUID) async throws -> TaskItem?
    func update(task: TaskItem) async throws -> TaskItem
}

@Suite("TaskController unit tests")
struct TaskControllerTests {

    // MARK: - Create task

    @Test("Create task succeeds with valid input")
    func createTaskSuccess() async throws {
        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.create(task: .any), use: { task in
            return task
        })

        let mock = MockTestTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Test task","priority":5}"#)
            ) { response in
                #expect(response.status == .created)
                let task = try JSONDecoder.appDecoder.decode(TaskItem.self, from: response.body)
                #expect(task.title == "Test task")
                #expect(task.priority == 5)
                #expect(task.status == .pending)
            }
        }

        @Sendable func isExpectedTask(_ task: TaskItem) -> Bool {
            task.title == "Test task" && task.priority == 5 && task.status == .pending
        }

        InOrder(strict: true, mock) { inOrder in
            inOrder.verify(mock).create(task: .matching(isExpectedTask))
        }
    }

    // MARK: - Get task not found

    @Test("Get task returns 404 when not found")
    func getTaskNotFound() async throws {
        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: nil)

        let mock = MockTestTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        let taskId = UUID()
        try await app.test(.router) { client in
            try await client.execute(uri: "/task/\(taskId)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }

        InOrder(strict: true, mock) { inOrder in
            inOrder.verify(mock).get(taskId: taskId)
        }
    }

    // MARK: - Update priority validation

    @Test("Update priority rejects values outside 1-10")
    func updatePriorityValidation() async throws {
        let mock = MockTestTaskRepository(expectations: .init())
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            let taskId = UUID()
            try await client.execute(
                uri: "/task/\(taskId)/priority",
                method: .patch,
                body: ByteBuffer(string: #"{"priority":15}"#)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }

        verifyNoInteractions(mock)
    }

    // MARK: - Cancel completed task returns conflict

    @Test("Cancel completed task returns 409 conflict")
    func cancelCompletedTaskConflict() async throws {
        let completedTask = TaskItem(
            title: "Done task",
            priority: 3,
            status: .completed
        )

        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: completedTask)

        let mock = MockTestTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(completedTask.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .conflict)
            }
        }

        InOrder(strict: true, mock) { inOrder in
            inOrder.verify(mock).get(taskId: completedTask.taskId)
        }
    }

    // MARK: - Cancel pending task succeeds

    @Test("Cancel pending task succeeds")
    func cancelPendingTaskSuccess() async throws {
        let pendingTask = TaskItem(
            title: "Pending task",
            priority: 5,
            status: .pending
        )

        var expectations = MockTestTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: pendingTask)
        when(expectations.update(task: .any), use: { task in
            return task
        })

        let mock = MockTestTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(pendingTask.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .ok)
                let task = try JSONDecoder.appDecoder.decode(TaskItem.self, from: response.body)
                #expect(task.status == .cancelled)
            }
        }

        @Sendable func isCancelledTask(_ task: TaskItem) -> Bool {
            task.taskId == pendingTask.taskId && task.status == .cancelled
        }

        InOrder(strict: true, mock) { inOrder in
            inOrder.verify(mock).get(taskId: pendingTask.taskId)
            inOrder.verify(mock).update(task: .matching(isCancelledTask))
        }
    }
}

// MARK: - JSON coding helpers

extension JSONDecoder {
    static let appDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
