import Foundation

public actor InMemoryTaskRepository: TaskRepository {
    private var storage: [UUID: TaskItem] = [:]

    public init() {}

    public func create(task: TaskItem) async throws -> TaskItem {
        storage[task.taskId] = task
        return task
    }

    public func get(taskId: UUID) async throws -> TaskItem? {
        storage[taskId]
    }

    public func update(task: TaskItem) async throws -> TaskItem {
        storage[task.taskId] = task
        return task
    }
}
