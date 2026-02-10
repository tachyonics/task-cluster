#if DynamoDB
import DynamoDBTables
import DynamoDBTasks
import Foundation
import TaskClusterModel
import Testing

@Suite("DynamoDBTaskRepository tests")
struct DynamoDBTaskRepositoryTests {

    // MARK: - Create and retrieve task

    @Test("Create stores item and get returns it with all fields intact")
    func createAndRetrieve() async throws {
        let table = InMemoryDynamoDBCompositePrimaryKeyTable()
        let repo = DynamoDBTaskRepository(table: table)

        let task = TaskItem(title: "Test task", priority: 5)
        let created = try await repo.create(task: task)

        #expect(created.taskId == task.taskId)

        let fetched = try await repo.get(taskId: task.taskId)
        let unwrapped = try #require(fetched)

        #expect(unwrapped.taskId == task.taskId)
        #expect(unwrapped.title == "Test task")
        #expect(unwrapped.priority == 5)
        #expect(unwrapped.status == .pending)
    }

    // MARK: - Get returns nil for unknown ID

    @Test("Get returns nil for non-existent task ID")
    func getReturnsNilForUnknownId() async throws {
        let table = InMemoryDynamoDBCompositePrimaryKeyTable()
        let repo = DynamoDBTaskRepository(table: table)

        let result = try await repo.get(taskId: UUID())
        #expect(result == nil)
    }

    // MARK: - Update modifies stored task

    @Test("Update persists changes to an existing task")
    func updateModifiesStoredTask() async throws {
        let table = InMemoryDynamoDBCompositePrimaryKeyTable()
        let repo = DynamoDBTaskRepository(table: table)

        var task = TaskItem(title: "Original", priority: 3)
        _ = try await repo.create(task: task)

        task.priority = 8
        task.title = "Updated"
        _ = try await repo.update(task: task)

        let fetched = try await repo.get(taskId: task.taskId)
        let unwrapped = try #require(fetched)

        #expect(unwrapped.priority == 8)
        #expect(unwrapped.title == "Updated")
    }

    // MARK: - Update throws for non-existent task

    @Test("Update throws notFound for non-existent task")
    func updateThrowsForNonExistentTask() async throws {
        let table = InMemoryDynamoDBCompositePrimaryKeyTable()
        let repo = DynamoDBTaskRepository(table: table)

        let task = TaskItem(title: "Ghost", priority: 1)

        await #expect(throws: TaskRepositoryError.self) {
            try await repo.update(task: task)
        }
    }

    // MARK: - Create duplicate throws

    @Test("Inserting the same taskId twice throws")
    func createDuplicateThrows() async throws {
        let table = InMemoryDynamoDBCompositePrimaryKeyTable()
        let repo = DynamoDBTaskRepository(table: table)

        let task = TaskItem(title: "Unique", priority: 2)
        _ = try await repo.create(task: task)

        await #expect(throws: (any Error).self) {
            try await repo.create(task: task)
        }
    }
}
#endif
