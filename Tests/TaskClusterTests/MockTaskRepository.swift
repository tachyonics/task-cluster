import Foundation
import Smockable
// `@Smock`'s expansion names `Testing.SourceLocation`; 6.4 requires the import to be visible here.
import Testing
import Wire

@testable import TaskClusterModel

@Smock
protocol TestTaskRepository: TaskRepository {
    func create(task: TaskItem) async throws -> TaskItem
    func get(taskId: UUID) async throws -> TaskItem?
    func update(task: TaskItem) async throws -> TaskItem
}

// A binding so the test module's graph resolves.
//
// WireGen builds a graph for every target that applies the plugins, and this one re-parses
// `TaskClusterApp` — so it sees `@Singleton TaskController<Repository>` and needs something to satisfy
// `Repository`. The tests never bootstrap that graph: each hand-builds a `TestGraph` around its own
// mock, because per-test expectations are the point. This binding exists only to make the graph
// complete, which is why it is `allowUnused`.
enum TestWiring {
    @Provides(allowUnused: true)
    static func repository() -> some TaskRepository {
        MockTestTaskRepository(expectations: MockTestTaskRepository.Expectations())
    }
}
