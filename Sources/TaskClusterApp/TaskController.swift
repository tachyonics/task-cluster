import Foundation
import TaskAPI
import TaskClusterModel

package struct TaskController<Repository: TaskRepository>: APIProtocol {
    var repository: Repository

    package func createTask(_ input: Operations.createTask.Input) async throws -> Operations.createTask.Output {
        let body =
            switch input.body {
            case .json(let value): value
            }

        guard (1...10).contains(body.priority) else {
            return .badRequest(.init())
        }

        let task = TaskItem(
            title: body.title,
            description: body.description,
            priority: body.priority,
            dueBy: body.dueBy
        )

        let created = try await repository.create(task: task)
        return .created(.init(body: .json(created.toResponse())))
    }

    package func getTask(_ input: Operations.getTask.Input) async throws -> Operations.getTask.Output {
        guard let taskId = UUID(uuidString: input.path.taskId) else {
            return .notFound(.init())
        }

        guard let task = try await repository.get(taskId: taskId) else {
            return .notFound(.init())
        }

        return .ok(.init(body: .json(task.toResponse())))
    }

    package func updateTaskPriority(
        _ input: Operations.updateTaskPriority.Input
    ) async throws -> Operations.updateTaskPriority.Output {
        let body =
            switch input.body {
            case .json(let value): value
            }

        guard (1...10).contains(body.priority) else {
            return .badRequest(.init())
        }

        guard let taskId = UUID(uuidString: input.path.taskId) else {
            return .notFound(.init())
        }

        guard var task = try await repository.get(taskId: taskId) else {
            return .notFound(.init())
        }

        task.priority = body.priority
        task.updatedAt = Date()
        let updated = try await repository.update(task: task)
        return .ok(.init(body: .json(updated.toResponse())))
    }

    package func cancelTask(_ input: Operations.cancelTask.Input) async throws -> Operations.cancelTask.Output {
        guard let taskId = UUID(uuidString: input.path.taskId) else {
            return .notFound(.init())
        }

        guard var task = try await repository.get(taskId: taskId) else {
            return .notFound(.init())
        }

        guard task.status == .pending || task.status == .running else {
            return .conflict(.init())
        }

        task.status = .cancelled
        task.updatedAt = Date()
        let updated = try await repository.update(task: task)
        return .ok(.init(body: .json(updated.toResponse())))
    }
}

extension TaskItem {
    package func toResponse() -> Components.Schemas.TaskItem {
        .init(
            taskId: taskId.uuidString,
            title: title,
            description: description,
            priority: priority,
            dueBy: dueBy,
            status: .init(rawValue: status.rawValue)!,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
