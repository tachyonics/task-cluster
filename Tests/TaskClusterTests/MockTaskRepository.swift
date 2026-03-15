import Foundation
import Smockable

@testable import TaskClusterModel

@Smock
protocol TestTaskRepository: TaskRepository {
    func create(task: TaskItem) async throws -> TaskItem
    func get(taskId: UUID) async throws -> TaskItem?
    func update(task: TaskItem) async throws -> TaskItem
}
