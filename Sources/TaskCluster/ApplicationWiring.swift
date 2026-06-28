import DynamoDBTables
import Logging
import TaskClusterApp
import TaskClusterDynamoDBModel
import Wire

enum ApplicationWiring {
    // Read off the graph at the composition root and handed to the
    // (non-Wire-managed) Application; nothing in the graph @Injects it,
    // so allowUnused silences the dead-binding warning.
    @Provides(allowUnused: true)
    static let logger = Logger(label: "TaskCluster")

    @Provides
    static let table = InMemoryDynamoDBCompositePrimaryKeyTable()
}

/// The composition root. Spelling the fully-concrete controller type here
/// is the single place that pins the implementation stack — Wire's
/// specialisation phase walks it down the chain (`TaskController` ->
/// `DynamoDBTaskRepository` -> `InMemoryDynamoDBCompositePrimaryKeyTable`),
/// constructing each generic `@Singleton` from the activated library
/// targets and resolving the table against `ApplicationWiring.table`.
@Singleton(allowUnused: true)
struct CompositionRoot {
    @Inject var controller: TaskController<DynamoDBTaskRepository<InMemoryDynamoDBCompositePrimaryKeyTable>>
}
