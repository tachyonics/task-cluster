import Foundation
// Used by @OpenAPIController's generated conformer, which the unused_import analyzer doesn't see.
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import TaskAPI
import TaskClusterModel
import Wire
import WireOpenAPI

@Singleton
// `spec:` names the module owning the generated `APIProtocol`. The bare form means the document beside
// the controller, and there is none here — this package keeps its spec in `TaskAPI` and its controllers
// in `TaskClusterApp`, which is exactly the split the argument exists for.
@OpenAPIController(spec: "TaskAPI")
// No `: APIProtocol` conformance. Operations are mounted individually now rather than through
// `registerHandlers`, and the conformance is generated onto the plugin-emitted proxy — a hand-written one
// here would require *every* operation in the document, which is the constraint that made splitting a
// spec across controllers impossible before M6d.
package struct TaskController<Repository: TaskRepository> {
    private let repository: Repository

    @Inject
    package init(repository: Repository) {
        self.repository = repository
    }

    @RawOperation
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

    @RawOperation
    package func getTask(_ input: Operations.getTask.Input) async throws -> Operations.getTask.Output {
        guard let taskId = UUID(uuidString: input.path.taskId) else {
            return .notFound(.init())
        }

        guard let task = try await repository.get(taskId: taskId) else {
            return .notFound(.init())
        }

        return .ok(.init(body: .json(task.toResponse())))
    }

    @RawOperation
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

    @RawOperation
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
