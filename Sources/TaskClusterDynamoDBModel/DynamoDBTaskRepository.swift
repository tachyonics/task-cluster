import DynamoDBTables
import Foundation
import TaskClusterModel

package enum TaskRepositoryError: Error {
    case notFound
}

package struct DynamoDBTaskRepository<Table: DynamoDBCompositePrimaryKeyTable & Sendable>: TaskRepository {
    package typealias TaskDatabaseItem = StandardTypedDatabaseItem<TaskItem>

    private let table: Table

    package init(table: Table) {
        self.table = table
    }

    private static func key(for taskId: UUID) -> StandardCompositePrimaryKey {
        StandardCompositePrimaryKey(partitionKey: "TASK", sortKey: "TASK#\(taskId)")
    }

    package func create(task: TaskItem) async throws -> TaskItem {
        let item = TaskDatabaseItem.newItem(withKey: Self.key(for: task.taskId), andValue: task)
        try await self.table.insertItem(item)
        return item.rowValue
    }

    package func get(taskId: UUID) async throws -> TaskItem? {
        let item: TaskDatabaseItem? = try await self.table.getItem(forKey: Self.key(for: taskId))
        return item?.rowValue
    }

    package func update(task: TaskItem) async throws -> TaskItem {
        let key = Self.key(for: task.taskId)
        guard let existingItem: TaskDatabaseItem = try await self.table.getItem(forKey: key) else {
            throw TaskRepositoryError.notFound
        }
        let updatedItem = existingItem.createUpdatedItem(withValue: task)
        try await self.table.updateItem(newItem: updatedItem, existingItem: existingItem)
        return updatedItem.rowValue
    }
}
