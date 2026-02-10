#if DynamoDB
import DynamoDBTables
import Foundation
import TaskClusterModel

public typealias TaskDatabaseItem = StandardTypedDatabaseItem<TaskItem>

public struct DynamoDBTaskRepository<Table: DynamoDBCompositePrimaryKeyTable & Sendable>: TaskRepository {
    let table: Table

    public init(table: Table) {
        self.table = table
    }

    public func create(task: TaskItem) async throws -> TaskItem {
        let key = StandardCompositePrimaryKey(
            partitionKey: "TASK",
            sortKey: "TASK#\(task.taskId)"
        )
        let item = TaskDatabaseItem.newItem(withKey: key, andValue: task)
        try await table.insertItem(item)
        return task
    }

    public func get(taskId: UUID) async throws -> TaskItem? {
        let key = StandardCompositePrimaryKey(
            partitionKey: "TASK",
            sortKey: "TASK#\(taskId)"
        )
        let item: TaskDatabaseItem? = try await table.getItem(forKey: key)
        return item?.rowValue
    }

    public func update(task: TaskItem) async throws -> TaskItem {
        let key = StandardCompositePrimaryKey(
            partitionKey: "TASK",
            sortKey: "TASK#\(task.taskId)"
        )
        guard let existing: TaskDatabaseItem = try await table.getItem(forKey: key) else {
            throw TaskRepositoryError.notFound
        }
        let updated = existing.createUpdatedItem(withValue: task)
        try await table.updateItem(newItem: updated, existingItem: existing)
        return task
    }
}

public enum TaskRepositoryError: Error {
    case notFound
}
#endif
