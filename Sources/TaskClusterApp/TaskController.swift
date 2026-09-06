import Foundation
// Used by @OpenAPIController's generated conformer, which the unused_import analyzer doesn't see.
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import TaskAPI
import TaskClusterModel
import Wire
import WireMVC
import WireOpenAPI

/// The refusals, as ordinary error types. Nothing about them knows which status they become — that lives
/// on the operation, in `@ErrorResponse`, which is what lets the same `NoSuchTask` answer 404 here and
/// something else on a controller that documents a different set of responses.
///
/// They exist because a typed operation returns the *success* body and nothing else. Where a
/// `@RawOperation` picked its response by constructing `.notFound(.init())`, the typed form has one
/// return type, so every other documented answer is reached by throwing.
package struct NoSuchTask: Error {}
package struct TaskNotCancellable: Error {}

@Singleton
// `spec:` names the module owning the generated `APIProtocol`. The bare form means the document beside
// the controller, and there is none here — this package keeps its spec in `TaskAPI` and its controllers
// in `TaskClusterApp`, which is exactly the split the argument exists for.
@OpenAPIController(spec: "TaskAPI")
// No `: APIProtocol` conformance. Operations are mounted individually now rather than through
// `registerHandlers`, and the conformance is generated onto the plugin-emitted proxy — a hand-written one
// here would require *every* operation in the document, which is the constraint that made splitting a
// spec across controllers impossible before M6d.
//
// Every operation is `@Operation` — the typed form. The parameters arrive as ordinary Swift arguments
// bound by WireMVC's own `@Path` and `@JSONBody`, the same wrappers `HealthController`'s `@Get` would
// use, and the return value is wrapped in the operation's response. `Operations.createTask.Input` and
// its `Output` are gone from this file entirely; what is left is the part that was ever this service's
// to write.
package struct TaskController<Repository: TaskRepository> {
    private let repository: Repository

    @Inject
    package init(repository: Repository) {
        self.repository = repository
    }

    /// The document declares one success — 201 — so which response the shim builds needs no saying; a
    /// second documented 2xx is what would force `@JSONResponse(status:)`.
    ///
    /// **No priority check in the body.** `1...10` is a fact about the API, not about this handler, so it
    /// is written where the API is described: `minimum`/`maximum` on `CreateTaskRequest.priority`. The
    /// generated validator reads the input before the forwarder calls this method, and a violation
    /// arrives here as a `WireOpenAPIRequestValidationError` — which is why the 400 is a mapping rather
    /// than a `guard`. The check also stops being something a client has to discover by being refused:
    /// it is in the document they generate from.
    @Operation
    @ErrorResponse(WireOpenAPIRequestValidationError.self, .badRequest)
    package func createTask(
        @JSONBody body: Components.Schemas.CreateTaskRequest
    ) async throws -> Components.Schemas.TaskItem {
        let task = TaskItem(
            title: body.title,
            description: body.description,
            priority: body.priority,
            dueBy: body.dueBy
        )

        return try await repository.create(task: task).toResponse()
    }

    /// `taskId` is a `String` because the document says so — `format: uuid` is a hint the generator does
    /// not turn into a `UUID`, and the typed form binds the type the document describes rather than one
    /// the handler would prefer. So the parse stays, and a value that is not a UUID is the same answer as
    /// a UUID naming nothing: the document declares no 400 on this path, and a caller cannot tell the two
    /// apart anyway.
    @Operation
    @ErrorResponse(NoSuchTask.self, .notFound)
    package func getTask(@Path taskId: String) async throws -> Components.Schemas.TaskItem {
        guard let taskId = UUID(uuidString: taskId), let task = try await repository.get(taskId: taskId) else {
            throw NoSuchTask()
        }

        return task.toResponse()
    }

    /// Both of this operation's failure responses, and they reach the handler from opposite directions:
    /// the 400 is thrown *at* it by the generated validator before it runs, the 404 by it. One
    /// `@ErrorResponse` list covers both because neither is special — a mapping matches on the error's
    /// type, wherever inside the forwarder it was raised.
    @Operation
    @ErrorResponse(WireOpenAPIRequestValidationError.self, .badRequest)
    @ErrorResponse(NoSuchTask.self, .notFound)
    package func updateTaskPriority(
        @Path taskId: String,
        @JSONBody body: Components.Schemas.UpdateTaskPriorityRequest
    ) async throws -> Components.Schemas.TaskItem {
        guard let taskId = UUID(uuidString: taskId), var task = try await repository.get(taskId: taskId) else {
            throw NoSuchTask()
        }

        task.priority = body.priority
        task.updatedAt = Date()
        return try await repository.update(task: task).toResponse()
    }

    /// The one refusal the document describes that no schema could: whether a task may be cancelled is a
    /// fact about its current status, which is state rather than shape. It stays a `guard` in the handler
    /// for exactly that reason — the spec is where the checks that do not need the database go.
    @Operation
    @ErrorResponse(NoSuchTask.self, .notFound)
    @ErrorResponse(TaskNotCancellable.self, .conflict)
    package func cancelTask(@Path taskId: String) async throws -> Components.Schemas.TaskItem {
        guard let taskId = UUID(uuidString: taskId), var task = try await repository.get(taskId: taskId) else {
            throw NoSuchTask()
        }

        guard task.status == .pending || task.status == .running else {
            throw TaskNotCancellable()
        }

        task.status = .cancelled
        task.updatedAt = Date()
        return try await repository.update(task: task).toResponse()
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
