import DynamoDBTables
import Foundation
import Testing

@testable import TaskClusterDynamoDBModel
@testable import TaskClusterModel

@Suite("DynamoDBTaskRepository Tests")
struct DynamoDBTaskRepositoryTests {
    // A well-known date to avoid precision issues
    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private static func makeTask(
        taskId: UUID = UUID(),
        title: String = "Test Task",
        description: String? = "A test task",
        priority: Int = 1,
        dueBy: Date? = nil,
        status: TaskStatus = .pending
    ) -> TaskItem {
        TaskItem(
            taskId: taskId,
            title: title,
            description: description,
            priority: priority,
            dueBy: dueBy,
            status: status,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    private static func makeRepository() -> DynamoDBTaskRepository<InMemoryDynamoDBCompositePrimaryKeyTable> {
        DynamoDBTaskRepository(table: InMemoryDynamoDBCompositePrimaryKeyTable())
    }

    @Test("Create a task and retrieve it by ID")
    func createAndGet() async throws {
        let repo = Self.makeRepository()
        let task = Self.makeTask(title: "Round-trip task", description: "Check all fields", priority: 5)

        let created = try await repo.create(task: task)
        #expect(created == task)

        let fetched = try await repo.get(taskId: task.taskId)
        #expect(fetched == task)
    }

    @Test("Get returns nil for a non-existent task ID")
    func getNonExistent() async throws {
        let repo = Self.makeRepository()

        let result = try await repo.get(taskId: UUID())
        #expect(result == nil)
    }

    @Test("Update modifies a stored task and changes persist")
    func updatePersists() async throws {
        let repo = Self.makeRepository()
        let task = Self.makeTask(title: "Original")

        _ = try await repo.create(task: task)

        var modified = task
        modified.title = "Updated"
        modified.status = .completed
        modified.updatedAt = Self.fixedDate

        let updated = try await repo.update(task: modified)
        #expect(updated == modified)

        let fetched = try await repo.get(taskId: task.taskId)
        #expect(fetched == modified)
    }

    @Test("Update throws for a non-existent task")
    func updateNonExistent() async throws {
        let repo = Self.makeRepository()
        let task = Self.makeTask()

        await #expect(throws: TaskRepositoryError.notFound) {
            try await repo.update(task: task)
        }
    }

    @Test("Creating the same task twice throws")
    func duplicateCreate() async throws {
        let repo = Self.makeRepository()
        let task = Self.makeTask()

        _ = try await repo.create(task: task)

        await #expect(throws: DynamoDBTableError.self) {
            try await repo.create(task: task)
        }
    }
}
