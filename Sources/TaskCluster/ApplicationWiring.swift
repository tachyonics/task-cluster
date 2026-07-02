import DynamoDBTables
import Logging
import Wire

enum ApplicationWiring {
    // Read off the graph at the composition root and handed to the
    // (non-Wire-managed) Application; nothing in the graph @Injects it,
    // so allowUnused silences the dead-binding warning.
    @Provides(allowUnused: true)
    static let logger = Logger(label: "TaskCluster")

    // The composition-root leaf: the single concrete choice, hidden behind an
    // opaque identity so the constrained-parameter chain resolves by identity
    // (`some TaskRepository` for the repo; the controller keeps its real
    // `TaskController<some TaskRepository>`) without spelling the nested concrete
    // stack. `InMemoryDynamoDBCompositePrimaryKeyTable` is named once, here; the
    // `& Sendable` matches the repository's `Table` constraint.
    @Provides
    static let table: some DynamoDBCompositePrimaryKeyTable & Sendable = InMemoryDynamoDBCompositePrimaryKeyTable()
}
