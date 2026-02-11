import Foundation

public protocol TaskRepository: Sendable {
    func create(task: TaskItem) async throws -> TaskItem
    func get(taskId: UUID) async throws -> TaskItem?
    func update(task: TaskItem) async throws -> TaskItem
}
