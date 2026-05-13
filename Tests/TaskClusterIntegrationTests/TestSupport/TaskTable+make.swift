import DynamoDBTables
import DynamoDBTablesSoto
import Foundation
import SotoCore
import SotoDynamoDB
import TaskClusterModel

/// Type-aliased view of the same DDB schema the production
/// `DynamoDBTaskRepository` uses: composite primary key (PK, SK), value of
/// `TaskItem`. Tests reach into the table directly — bypassing the
/// repository — so DB-level state setup and assertion is decoupled from the
/// service code under test.
typealias TaskDatabaseItem = StandardTypedDatabaseItem<TaskItem>

/// Mirrors `DynamoDBTaskRepository.key(for:)` so seeded rows land at the
/// same PK/SK the service expects.
func taskKey(_ taskId: UUID) -> StandardCompositePrimaryKey {
    StandardCompositePrimaryKey(partitionKey: "TASK", sortKey: "TASK#\(taskId)")
}

/// Builds a Soto-backed table pointed at the LocalStack DynamoDB endpoint
/// the trait wired in. Caller is responsible for shutting down the
/// underlying `AWSClient` via the returned handle.
func makeTaskTable(
    endpoint: String,
    tableName: String,
    region: String = "us-east-1"
) -> (table: SotoDynamoDBCompositePrimaryKeyTable, shutdown: @Sendable () async throws -> Void) {
    let awsClient = AWSClient(
        credentialProvider: .static(accessKeyId: "test", secretAccessKey: "test")
    )
    let dynamoDB = SotoDynamoDB.DynamoDB(
        client: awsClient,
        region: Region(rawValue: region),
        endpoint: endpoint
    )
    let table = SotoDynamoDBCompositePrimaryKeyTable(
        tableName: tableName,
        client: dynamoDB
    )
    return (table, { try await awsClient.shutdown() })
}

// MARK: - Seed / read helpers

/// Inserts a task row directly at the storage layer. Used to set up
/// preconditions before calling the service.
func seedTask(_ task: TaskItem, into table: SotoDynamoDBCompositePrimaryKeyTable) async throws {
    let item = TaskDatabaseItem.newItem(withKey: taskKey(task.taskId), andValue: task)
    try await table.insertItem(item)
}

/// Reads a task row directly from storage. Used in assertions to confirm
/// the service's effect on persisted state.
func readTask(
    _ taskId: UUID,
    from table: SotoDynamoDBCompositePrimaryKeyTable
) async throws -> TaskItem? {
    let row: TaskDatabaseItem? = try await table.getItem(forKey: taskKey(taskId))
    return row?.rowValue
}
