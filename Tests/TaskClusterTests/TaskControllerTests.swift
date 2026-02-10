import Foundation
import Hummingbird
import HummingbirdTesting
import Smockable
import TaskClusterApp
import TaskClusterModel
import Testing

@Suite("TaskController unit tests")
struct TaskControllerTests {

    // MARK: - Create task

    @Test("Create task succeeds with valid input")
    func createTaskSuccess() async throws {
        var expectations = MockTaskRepository.Expectations()
        when(expectations.create(task: .any), use: { task in
            return task
        })

        let mock = MockTaskRepository(expectations: expectations)
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
    }

    // MARK: - Get task not found

    @Test("Get task returns 404 when not found")
    func getTaskNotFound() async throws {
        var expectations = MockTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: nil)

        let mock = MockTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            let taskId = UUID()
            try await client.execute(uri: "/task/\(taskId)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    // MARK: - Update priority validation

    @Test("Update priority rejects values outside 1-10")
    func updatePriorityValidation() async throws {
        let mock = MockTaskRepository(expectations: .init())
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
    }

    // MARK: - Cancel completed task returns conflict

    @Test("Cancel completed task returns 409 conflict")
    func cancelCompletedTaskConflict() async throws {
        let completedTask = TaskItem(
            title: "Done task",
            priority: 3,
            status: .completed
        )

        var expectations = MockTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: completedTask)

        let mock = MockTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(completedTask.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .conflict)
            }
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

        var expectations = MockTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: pendingTask)
        when(expectations.update(task: .any), use: { task in
            return task
        })

        let mock = MockTaskRepository(expectations: expectations)
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
