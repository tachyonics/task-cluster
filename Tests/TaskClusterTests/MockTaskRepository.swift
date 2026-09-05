import Foundation
import Smockable
import Synchronization
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

/// The repository the *suite's* graph binds, superseding `DynamoDBTaskRepository` for the `TaskRepository`
/// key.
///
/// This target re-composes the app's graph — `TaskCluster`, `TaskClusterApp` and `TaskClusterDynamoDBModel`
/// all depend on the `Wire` product, which is what marks a module composable now that the
/// `_WireExports.swift` marker is retired — so `@Replaces` makes this win over the real binding instead of
/// colliding with it. Binding it here is also what keeps AWS out of the suite: nothing reaches
/// `ApplicationWiring.table` any more, so the Soto table, the DynamoDB client and the `AWSClient` are pruned
/// and never constructed. The suite stands up the app's *real* router, error tiers and `@NotFound`, with no
/// AWS in the graph.
///
/// **Why a forwarder rather than the mock itself.** A graph binding is constructed once per suite, but these
/// tests set their expectations per test — that is most of what they assert. So the binding is a stable
/// forwarder and the mock behind it is swapped by ``withRepository(_:)``. That is the seam the keyed
/// `@BindType` harness would otherwise provide; it cannot be used here, because the keyed harness matches
/// `@Controller` subjects only and `TaskController` is an `@OpenAPIController` (see the note in
/// `TaskControllerTests`).
@Singleton(as: TaskRepository.self)
@Replaces
struct SuppliedTaskRepository: TaskRepository {
    @Inject init() {}

    func create(task: TaskItem) async throws -> TaskItem {
        try await Self.current.create(task: task)
    }

    func get(taskId: UUID) async throws -> TaskItem? {
        try await Self.current.get(taskId: taskId)
    }

    func update(task: TaskItem) async throws -> TaskItem {
        try await Self.current.update(task: task)
    }

    private static let supplied = Mutex<MockTestTaskRepository?>(nil)

    private static var current: MockTestTaskRepository {
        guard let mock = supplied.withLock({ $0 }) else {
            // A request reaching the repository with nothing supplied is a test-authoring mistake, not a
            // scenario — failing loudly here beats a confusing decode error further down.
            fatalError("no mock supplied: drive requests through withRepository(_:)")
        }
        return mock
    }

    static func install(_ mock: MockTestTaskRepository?) {
        supplied.withLock { $0 = mock }
    }
}

/// Run `body` with `mock` answering every repository call the app makes.
///
/// The suite is `.serialized` because the supplied mock is suite-wide state; two tests supplying different
/// mocks concurrently would cross. That is the cost of the forwarder seam, and it is why the keyed harness —
/// which isolates concurrent requests by correlation id instead — is the better shape once an
/// `@OpenAPIController` can be one of its subjects.
func withRepository<R>(
    _ mock: MockTestTaskRepository,
    _ body: () async throws -> R
) async throws -> R {
    SuppliedTaskRepository.install(mock)
    defer { SuppliedTaskRepository.install(nil) }
    return try await body()
}
