import DynamoDBTables
import Logging
import Wire

enum ApplicationWiring {
    @Provides
    static let logger = Logger(label: "TaskCluster")

    @Provides
    static let table = InMemoryDynamoDBCompositePrimaryKeyTable()
}
