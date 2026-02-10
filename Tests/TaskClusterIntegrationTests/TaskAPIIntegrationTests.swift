import Foundation
import Hummingbird
import HummingbirdTesting
import TaskClusterApp
import TaskClusterModel
import Testing

@Suite("Task API integration tests")
struct TaskAPIIntegrationTests {

    func buildTestApp() throws -> some ApplicationProtocol {
        try buildApplication(repository: InMemoryTaskRepository())
    }

    // MARK: - POST /task creates and returns task with 201

    @Test("POST /task creates a task")
    func createTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Integration test task","priority":7}"#)
            ) { response in
                #expect(response.status == .created)
                let task = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(task.title == "Integration test task")
                #expect(task.priority == 7)
                #expect(task.status == .pending)
            }
        }
    }

    // MARK: - GET /task/{id} returns the created task

    @Test("GET /task/{id} returns a previously created task")
    func getCreatedTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            // Create a task first
            let createdTask = try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Fetch me","priority":3}"#)
            ) { response -> TaskItem in
                #expect(response.status == .created)
                return try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
            }

            // Fetch it
            try await client.execute(uri: "/task/\(createdTask.taskId)", method: .get) { response in
                #expect(response.status == .ok)
                let fetched = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(fetched.taskId == createdTask.taskId)
                #expect(fetched.title == "Fetch me")
            }
        }
    }

    // MARK: - GET /task/{unknown-id} returns 404

    @Test("GET /task/{unknown-id} returns 404")
    func getUnknownTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            let unknownId = UUID()
            try await client.execute(uri: "/task/\(unknownId)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    // MARK: - PATCH /task/{id}/priority updates correctly

    @Test("PATCH /task/{id}/priority updates the priority")
    func updatePriority() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            // Create a task
            let created = try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Update me","priority":3}"#)
            ) { response -> TaskItem in
                return try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
            }

            // Update priority
            try await client.execute(
                uri: "/task/\(created.taskId)/priority",
                method: .patch,
                body: ByteBuffer(string: #"{"priority":9}"#)
            ) { response in
                #expect(response.status == .ok)
                let updated = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(updated.priority == 9)
                #expect(updated.taskId == created.taskId)
            }
        }
    }

    // MARK: - POST /task/{id}/cancel changes status

    @Test("POST /task/{id}/cancel cancels a pending task")
    func cancelTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            // Create a task
            let created = try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Cancel me","priority":2}"#)
            ) { response -> TaskItem in
                return try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
            }

            // Cancel it
            try await client.execute(
                uri: "/task/\(created.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .ok)
                let cancelled = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(cancelled.status == .cancelled)
                #expect(cancelled.taskId == created.taskId)
            }
        }
    }
}

// MARK: - JSON coding helpers

extension JSONDecoder {
    static let testDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
