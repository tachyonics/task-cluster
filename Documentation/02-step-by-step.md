# Step-by-Step: Building task-cluster with the Hummingbird Template

This guide walks through building the task-cluster service using the Hummingbird project template with OpenAPI generator support. Each step produces code you can compile, and the guide explains *why* things are written the way they are -- not just *what* to type.

**Prerequisites:** Swift 6.2+ toolchain installed. You can verify with `swift --version`.

## Step 1: Scaffold from the Hummingbird Template

The Hummingbird project provides an official template that scaffolds a working server project. Clone it and run the configuration script:

```bash
git clone https://github.com/hummingbird-project/template.git task-cluster
cd task-cluster
./configure.sh
```

The script asks a series of questions. Answer:
- **Package name:** `task-cluster`
- **Use OpenAPI?** Yes
- **Use Lambda?** No (unless you want Lambda support)

This generates a working hello-world server with OpenAPI generator already wired up. Before making any changes, verify the scaffold compiles:

```bash
swift build
swift run task-cluster
```

You should see the server start on `http://localhost:8080`.

## Step 2: Understand What the Template Generated

The template creates a project structure that looks like this:

```
task-cluster/
├── Package.swift
├── Sources/
│   ├── App/
│   │   ├── App.swift                    # @main entry point
│   │   ├── Application+build.swift      # buildApplication() + buildRouter()
│   │   └── APIImplementation.swift      # APIProtocol conformance (hello world, we'll replace this)
│   └── AppAPI/
│       ├── openapi.yaml                 # OpenAPI spec (hello world)
│       ├── openapi-generator-config.yaml
│       └── AppAPI.swift                 # Empty placeholder (SPM requires a .swift file)
└── Tests/
    └── AppTests/
```

Key things to notice:

**`Package.swift`** includes these dependencies:
- `hummingbird` -- the web framework
- `swift-configuration` -- for reading hostname/port from environment, CLI args, or `.env` files
- `swift-openapi-generator` -- the build plugin that generates Swift code from the OpenAPI spec
- `swift-openapi-runtime` -- runtime types used by generated code
- `swift-openapi-hummingbird` -- makes Hummingbird's `Router` work as an OpenAPI `ServerTransport`

**`AppAPI` target** has the `OpenAPIGenerator` build plugin:
```swift
.target(
    name: "AppAPI",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    ],
    plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
    ]
)
```

The plugin reads `openapi.yaml` and `openapi-generator-config.yaml` from the target's source directory and generates Swift types at compile time. You never see the generated files in your source tree -- they live in `.build/plugins/outputs/`.

**`openapi-generator-config.yaml`** tells the plugin what to generate:
```yaml
generate:
  - types
  - server
accessModifier: package
filter:
  tags:
    - Tasks
```

`types` generates `Components.Schemas.*` and `Operations.*`. `server` generates the `APIProtocol` and `registerHandlers(on:)`. `package` access means the generated types are visible within the package but not exported. The `filter` section tells the generator to only include operations tagged with `Tasks` -- this lets multiple API targets share the same root spec while each generating only its own subset.

## Step 3: Restructure for task-cluster

The template uses a flat two-target layout (`App` + `AppAPI`). For task-cluster, we want a more layered architecture with separate model and app targets. Rename and restructure:

```
Sources/
├── TaskAPI/                           # Was: AppAPI
│   ├── openapi.yaml → ../../openapi.yaml  # Symlink to root spec
│   ├── openapi-generator-config.yaml      # filter: tags: [Tasks]
│   └── TaskAPI.swift
├── TaskClusterModel/                  # New: domain types + repository
│   ├── TaskModel.swift
│   ├── TaskRepository.swift
│   └── InMemoryTaskRepository.swift
├── TaskClusterApp/                    # Was: App (minus entry point)
│   ├── TaskController.swift           # APIProtocol conformance (task domain)
│   └── Application+build.swift
├── TaskClusterService/                # New: executable entry point
│   └── App.swift
└── DynamoDBTasks/                     # New: optional DynamoDB backend
    └── DynamoDBTaskRepository.swift
```

Update `Package.swift` to reflect the new targets. The key additions beyond what the template provides are:
- `TaskClusterModel` target (depends on Smockable)
- `TaskClusterApp` depends on `TaskAPI`, `TaskClusterModel`, `OpenAPIHummingbird`
- `DynamoDBTasks` with trait-gated dependency
- Two test targets instead of one

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "task-cluster",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "task-cluster", targets: ["TaskClusterService"]),
    ],
    traits: [
        "DynamoDB",
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0", traits: [.defaults, "CommandLineArguments"]),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.7.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-hummingbird.git", from: "2.0.1"),
        .package(url: "https://github.com/tachyonics/smockable.git", from: "0.5.0"),
        .package(url: "https://github.com/swift-server-community/dynamo-db-tables.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "TaskAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),

        .target(
            name: "TaskClusterModel",
            dependencies: [
                .product(name: "Smockable", package: "smockable"),
            ]
        ),

        .target(
            name: "TaskClusterApp",
            dependencies: [
                "TaskAPI",
                "TaskClusterModel",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
            ]
        ),

        .executableTarget(
            name: "TaskClusterService",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterModel",
                .product(name: "Configuration", package: "swift-configuration"),
            ]
        ),

        .target(
            name: "DynamoDBTasks",
            dependencies: [
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables",
                         condition: .when(traits: ["DynamoDB"])),
            ]
        ),

        .testTarget(
            name: "TaskClusterTests",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterModel",
                .product(name: "Smockable", package: "smockable"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),

        .testTarget(
            name: "TaskClusterIntegrationTests",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterModel",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
```

## Step 4: Write the OpenAPI Spec

Replace the template's hello-world spec with `openapi.yaml` at the project root. Each API target symlinks to this file and uses tag-based filtering to generate only its operations. Create the symlink: `ln -s ../../openapi.yaml Sources/TaskAPI/openapi.yaml`.

The root spec:

```yaml
openapi: "3.1.0"
info:
  title: task-cluster API
  description: Cloud task management service for submitting, prioritising, and executing tasks.
  version: "0.1.0"

servers:
  - url: http://localhost:8080
    description: Local development server

paths:
  /task:
    post:
      operationId: createTask
      summary: Create a new task
      tags: [Tasks]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/CreateTaskRequest"
      responses:
        "201":
          description: Task created successfully
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/TaskResponse"
        "400":
          description: Invalid request (e.g. priority out of range)

  /task/{taskId}:
    get:
      operationId: getTask
      summary: Get a task by ID
      tags: [Tasks]
      parameters:
        - name: taskId
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        "200":
          description: Task found
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/TaskResponse"
        "404":
          description: Task not found

  /task/{taskId}/priority:
    patch:
      operationId: updateTaskPriority
      summary: Update a task's priority
      tags: [Tasks]
      parameters:
        - name: taskId
          in: path
          required: true
          schema:
            type: string
            format: uuid
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/UpdatePriorityRequest"
      responses:
        "200":
          description: Priority updated
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/TaskResponse"
        "400":
          description: Invalid priority value
        "404":
          description: Task not found

  /task/{taskId}/cancel:
    post:
      operationId: cancelTask
      summary: Cancel a task
      tags: [Tasks]
      parameters:
        - name: taskId
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        "200":
          description: Task cancelled
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/TaskResponse"
        "404":
          description: Task not found
        "409":
          description: Task cannot be cancelled (already completed, failed, or cancelled)

components:
  schemas:
    TaskStatus:
      type: string
      enum:
        - pending
        - running
        - completed
        - failed
        - cancelled

    CreateTaskRequest:
      type: object
      required:
        - title
        - priority
      properties:
        title:
          type: string
          minLength: 1
        description:
          type: string
        priority:
          type: integer
          minimum: 1
          maximum: 10
        dueBy:
          type: string
          format: date-time

    UpdatePriorityRequest:
      type: object
      required:
        - priority
      properties:
        priority:
          type: integer
          minimum: 1
          maximum: 10

    TaskResponse:
      type: object
      required:
        - taskId
        - title
        - priority
        - status
        - createdAt
        - updatedAt
      properties:
        taskId:
          type: string
          format: uuid
        title:
          type: string
        description:
          type: string
        priority:
          type: integer
        status:
          $ref: "#/components/schemas/TaskStatus"
        dueBy:
          type: string
          format: date-time
        createdAt:
          type: string
          format: date-time
        updatedAt:
          type: string
          format: date-time
```

Design choices worth calling out:

- **Cancel is `POST`, not `PATCH` or `DELETE`.** Cancelling is an action that triggers a state transition, not a partial update to a field. POST communicates intent more clearly.
- **Priority update is `PATCH` on a sub-resource.** `PATCH /task/{id}/priority` is more specific than `PATCH /task/{id}` with a partial body. It makes the API self-documenting and keeps each endpoint focused.
- **409 Conflict for invalid cancellations.** If a task is already completed, failed, or cancelled, cancelling it again is a conflict with the current state, not a "not found" or "bad request".
- **`operationId` values become Swift method names.** `createTask`, `getTask`, `updateTaskPriority`, `cancelTask` are chosen to read well as Swift function names.

## Step 5: Define Domain Models

Create `Sources/TaskClusterModel/TaskModel.swift`:

```swift
import Foundation

public enum TaskStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

public struct TaskItem: Codable, Sendable {
    public var taskId: UUID
    public var title: String
    public var description: String?
    public var priority: Int
    public var dueBy: Date?
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        taskId: UUID = UUID(),
        title: String,
        description: String? = nil,
        priority: Int,
        dueBy: Date? = nil,
        status: TaskStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.taskId = taskId
        self.title = title
        self.description = description
        self.priority = priority
        self.dueBy = dueBy
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

Notice there are no request DTOs (`CreateTaskRequest`, `UpdatePriorityRequest`) here. Those types are generated from the OpenAPI spec by `swift-openapi-generator` and live in `Components.Schemas.*`. The model target only defines the domain type used for storage.

`TaskItem` uses `var` properties so the API implementation can mutate a copy when updating priority or cancelling. The init provides sensible defaults (`UUID()` for taskId, `.pending` for status, `Date()` for timestamps) so callers only need to specify the fields they care about.

## Step 6: Define the Repository Protocol

Create `Sources/TaskClusterModel/TaskRepository.swift`:

```swift
import Foundation
import Smockable

@Smock(accessLevel: .public)
public protocol TaskRepository: Sendable {
    func create(task: TaskItem) async throws -> TaskItem
    func get(taskId: UUID) async throws -> TaskItem?
    func update(task: TaskItem) async throws -> TaskItem
}
```

The `@Smock` macro generates a `MockTaskRepository` at compile time for use in tests.

## Step 7: Implement In-Memory Storage

Create `Sources/TaskClusterModel/InMemoryTaskRepository.swift`:

```swift
import Foundation

public actor InMemoryTaskRepository: TaskRepository {
    private var storage: [UUID: TaskItem] = [:]

    public init() {}

    public func create(task: TaskItem) async throws -> TaskItem {
        storage[task.taskId] = task
        return task
    }

    public func get(taskId: UUID) async throws -> TaskItem? {
        storage[taskId]
    }

    public func update(task: TaskItem) async throws -> TaskItem {
        storage[task.taskId] = task
        return task
    }
}
```

At this point you can verify the model target compiles:

```bash
swift build --target TaskClusterModel
```

You can also verify the API target compiles:

```bash
swift build --target TaskAPI
```

## Step 8: Implement the Task Controller

This is where the OpenAPI generator pays off. Each API domain gets its own controller that conforms to the generated `APIProtocol`. Create `Sources/TaskClusterApp/TaskController.swift`:

```swift
import Foundation
import Hummingbird
import OpenAPIRuntime
import TaskAPI
import TaskClusterModel

struct TaskController<Repository: TaskRepository>: APIProtocol {
    let repository: Repository

    func createTask(_ input: Operations.createTask.Input) async throws -> Operations.createTask.Output {
        let body: Components.Schemas.CreateTaskRequest
        switch input.body {
        case .json(let value):
            body = value
        }

        guard (1...10).contains(body.priority) else {
            return .badRequest(.init())
        }

        let now = Date()
        let task = TaskItem(
            title: body.title,
            description: body.description,
            priority: body.priority,
            dueBy: body.dueBy,
            status: .pending,
            createdAt: now,
            updatedAt: now
        )

        let created = try await repository.create(task: task)
        return .created(.init(body: .json(created.toResponse())))
    }

    func getTask(_ input: Operations.getTask.Input) async throws -> Operations.getTask.Output {
        guard let taskId = UUID(uuidString: input.path.taskId) else {
            return .notFound(.init())
        }

        guard let task = try await repository.get(taskId: taskId) else {
            return .notFound(.init())
        }

        return .ok(.init(body: .json(task.toResponse())))
    }

    func updateTaskPriority(_ input: Operations.updateTaskPriority.Input) async throws -> Operations.updateTaskPriority.Output {
        guard let taskId = UUID(uuidString: input.path.taskId) else {
            return .notFound(.init())
        }

        let body: Components.Schemas.UpdatePriorityRequest
        switch input.body {
        case .json(let value):
            body = value
        }

        guard (1...10).contains(body.priority) else {
            return .badRequest(.init())
        }

        guard var task = try await repository.get(taskId: taskId) else {
            return .notFound(.init())
        }

        task.priority = body.priority
        task.updatedAt = Date()

        let updated = try await repository.update(task: task)
        return .ok(.init(body: .json(updated.toResponse())))
    }

    func cancelTask(_ input: Operations.cancelTask.Input) async throws -> Operations.cancelTask.Output {
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
    func toResponse() -> Components.Schemas.TaskResponse {
        .init(
            taskId: taskId.uuidString,
            title: title,
            description: description,
            priority: priority,
            status: Components.Schemas.TaskStatus(rawValue: status.rawValue)!,
            dueBy: dueBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
```

The name `TaskController` follows the convention of one controller per API domain. When you add a second domain (e.g. billing), you'd create a `BillingAPI` target (with its own symlink to the root spec and a `filter: tags: [Billing]` config) and a `BillingController` conforming to its generated `APIProtocol`.

Several things to notice about how OpenAPI-generated types work:

**Input body is an enum.** `input.body` is `Operations.createTask.Input.Body`, which is an enum with one case per content type. Since our spec only declares `application/json`, there's only `.json(Components.Schemas.CreateTaskRequest)`. The `switch` is exhaustive -- the compiler ensures you handle every content type.

**Output is an enum of status codes.** Each method returns an `Output` enum where each case corresponds to a response status code declared in the spec. `.created(.init(body: .json(...)))` means "return HTTP 201 with a JSON body". `.notFound(.init())` means "return HTTP 404 with no body" (because the spec declares no content for 404).

**Type-safe status codes.** You can't accidentally return `.conflict` from `getTask` -- the compiler won't let you, because the spec only declares 200 and 404 for that operation.

**Domain model conversion.** The `toResponse()` helper converts from `TaskItem` (domain model) to `Components.Schemas.TaskResponse` (API response type). The domain model uses `UUID` for `taskId` while the API uses `String` (with `format: uuid`), so we call `.uuidString`.

## Step 9: Wire Up the Application

Create `Sources/TaskClusterApp/Application+build.swift`:

```swift
import Foundation
import Hummingbird
import Logging
import OpenAPIHummingbird
import OpenAPIRuntime
import TaskClusterModel

public typealias AppRequestContext = BasicRequestContext

public func buildApplication(
    repository: some TaskRepository,
    configuration: ApplicationConfiguration = .init(address: .hostname("127.0.0.1", port: 8080)),
    logger: Logger = Logger(label: "task-cluster")
) throws -> some ApplicationProtocol {
    let router = try buildRouter(repository: repository)
    return Application(
        router: router,
        configuration: configuration,
        logger: logger
    )
}

func buildRouter(repository: some TaskRepository) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)

    router.addMiddleware {
        LogRequestsMiddleware(.info)
    }

    router.get("/") { _, _ in
        "task-cluster is running"
    }

    let taskController = TaskController(repository: repository)
    try taskController.registerHandlers(on: router)

    // Future domains would register here too:
    // let billingController = BillingController(billingService: billing)
    // try billingController.registerHandlers(on: router)

    return router
}
```

The key line is `try taskController.registerHandlers(on: router)`. This is generated by `swift-openapi-generator` and registers one route per operation in the spec. The `swift-openapi-hummingbird` package makes `Router` conform to `ServerTransport`, which is the protocol that `registerHandlers` expects.

Each API domain gets its own controller that registers on the same router. Paths can't collide, but that's enforced naturally by giving each domain its own path prefix (`/task/*`, `/invoice/*`, etc.).

Note that `buildApplication` is now `throws` (not just `async throws`) because `registerHandlers` can throw. This is a small difference from the hand-written controller approach where route registration was infallible.

## Step 10: Create the Entry Point

Create `Sources/TaskClusterService/App.swift`:

```swift
import Configuration
import Hummingbird
import TaskClusterApp
import TaskClusterModel

@main
struct App {
    static func main() async throws {
        let reader = try await ConfigReader(providers: [
            CommandLineArgumentsProvider(),
            EnvironmentVariablesProvider(),
            EnvironmentVariablesProvider(environmentFilePath: ".env", allowMissing: true),
            InMemoryProvider(values: [
                "http.serverName": "task-cluster",
            ]),
        ])

        let repository = InMemoryTaskRepository()
        let app = try buildApplication(
            repository: repository,
            configuration: .init(reader: reader.scoped(to: "http"))
        )
        try await app.runService()
    }
}
```

This uses `swift-configuration` instead of `ArgumentParser`. The `ConfigReader` checks configuration sources in priority order:

1. **Command-line arguments**: `swift run task-cluster --http.host 0.0.0.0 --http.port 3000`
2. **Environment variables**: `HTTP_HOST=0.0.0.0 HTTP_PORT=3000 swift run task-cluster`
3. **`.env` file**: Create a `.env` file with `HTTP_PORT=3000`
4. **In-memory defaults**: The `InMemoryProvider` at the bottom provides fallback values

`ApplicationConfiguration.init(reader:)` reads `host`, `port`, and `serverName` from the reader scoped to the `"http"` prefix. This is Hummingbird's built-in integration with `swift-configuration`.

At this point the application should build and run:

```bash
swift build
swift run task-cluster
```

Test it with curl:

```bash
curl -X POST http://localhost:8080/task \
  -H "Content-Type: application/json" \
  -d '{"title":"My first task","priority":5}'
```

## Step 11: Add the DynamoDB Implementation

Create `Sources/DynamoDBTasks/DynamoDBTaskRepository.swift`:

```swift
#if DynamoDB
import DynamoDBTables
import Foundation
import TaskClusterModel

public typealias TaskDatabaseItem = StandardTypedDatabaseItem<TaskItem>

public struct DynamoDBTaskRepository: TaskRepository {
    let table: DynamoDBCompositePrimaryKeyTable

    public init(table: DynamoDBCompositePrimaryKeyTable) {
        self.table = table
    }

    public func create(task: TaskItem) async throws -> TaskItem {
        let key = StandardCompositePrimaryKey(
            partitionKey: "TASK",
            sortKey: "TASK#\(task.taskId)"
        )
        let item = TaskDatabaseItem.newItem(withKey: key, andValue: task)
        try await table.insertItem(item)
        return task
    }

    public func get(taskId: UUID) async throws -> TaskItem? {
        let key = StandardCompositePrimaryKey(
            partitionKey: "TASK",
            sortKey: "TASK#\(taskId)"
        )
        let item: TaskDatabaseItem? = try await table.getItem(forKey: key)
        return item?.rowValue
    }

    public func update(task: TaskItem) async throws -> TaskItem {
        let key = StandardCompositePrimaryKey(
            partitionKey: "TASK",
            sortKey: "TASK#\(task.taskId)"
        )
        guard let existing: TaskDatabaseItem = try await table.getItem(forKey: key) else {
            throw TaskRepositoryError.notFound
        }
        let updated = existing.createUpdatedItem(withValue: task)
        try await table.updateItem(newItem: updated, existingItem: existing)
        return task
    }
}

enum TaskRepositoryError: Error {
    case notFound
}
#endif
```

Verify this compiles with:

```bash
swift build --traits DynamoDB
```

## Step 12: Write Unit Tests

Create `Tests/TaskClusterTests/TaskControllerTests.swift`:

```swift
import Foundation
import Hummingbird
import HummingbirdTesting
import Smockable
import TaskClusterApp
import TaskClusterModel
import Testing

@Suite("TaskController unit tests")
struct TaskControllerTests {

    @Test("Create task succeeds with valid input")
    func createTaskSuccess() async throws {
        var expectations = MockTaskRepository.Expectations()
        when(expectations.create(task: .any), use: { task in
            return task
        })

        let mock = MockTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Test task","priority":5}"#)
            ) { response in
                #expect(response.status == .created)
                let task = try JSONDecoder.appDecoder.decode(TaskItem.self, from: response.body)
                #expect(task.title == "Test task")
                #expect(task.priority == 5)
                #expect(task.status == .pending)
            }
        }
    }

    @Test("Get task returns 404 when not found")
    func getTaskNotFound() async throws {
        var expectations = MockTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: nil)

        let mock = MockTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            let taskId = UUID()
            try await client.execute(uri: "/task/\(taskId)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("Update priority rejects values outside 1-10")
    func updatePriorityValidation() async throws {
        let mock = MockTaskRepository(expectations: .init())
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            let taskId = UUID()
            try await client.execute(
                uri: "/task/\(taskId)/priority",
                method: .patch,
                body: ByteBuffer(string: #"{"priority":15}"#)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("Cancel completed task returns 409 conflict")
    func cancelCompletedTaskConflict() async throws {
        let completedTask = TaskItem(
            title: "Done task",
            priority: 3,
            status: .completed
        )

        var expectations = MockTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: completedTask)

        let mock = MockTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(completedTask.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .conflict)
            }
        }
    }

    @Test("Cancel pending task succeeds")
    func cancelPendingTaskSuccess() async throws {
        let pendingTask = TaskItem(
            title: "Pending task",
            priority: 5,
            status: .pending
        )

        var expectations = MockTaskRepository.Expectations()
        when(expectations.get(taskId: .any), return: pendingTask)
        when(expectations.update(task: .any), use: { task in
            return task
        })

        let mock = MockTaskRepository(expectations: expectations)
        let app = try buildApplication(repository: mock)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task/\(pendingTask.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .ok)
                let task = try JSONDecoder.appDecoder.decode(TaskItem.self, from: response.body)
                #expect(task.status == .cancelled)
            }
        }
    }
}

extension JSONDecoder {
    static let appDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

The tests send raw JSON strings as `ByteBuffer` request bodies and decode the responses as `TaskItem`. This works because the OpenAPI-generated response format matches `TaskItem`'s `Codable` representation -- the JSON property names are the same. We're testing the full HTTP contract through `HummingbirdTesting`'s `.router` transport.

## Step 13: Write Integration Tests

Create `Tests/TaskClusterIntegrationTests/TaskAPIIntegrationTests.swift`:

```swift
import Foundation
import Hummingbird
import HummingbirdTesting
import TaskClusterApp
import TaskClusterModel
import Testing

@Suite("Task API integration tests")
struct TaskAPIIntegrationTests {

    func buildTestApp() throws -> some ApplicationProtocol {
        try buildApplication(repository: InMemoryTaskRepository())
    }

    @Test("POST /task creates a task")
    func createTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Integration test task","priority":7}"#)
            ) { response in
                #expect(response.status == .created)
                let task = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(task.title == "Integration test task")
                #expect(task.priority == 7)
                #expect(task.status == .pending)
            }
        }
    }

    @Test("GET /task/{id} returns a previously created task")
    func getCreatedTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            let createdTask = try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Fetch me","priority":3}"#)
            ) { response -> TaskItem in
                #expect(response.status == .created)
                return try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
            }

            try await client.execute(uri: "/task/\(createdTask.taskId)", method: .get) { response in
                #expect(response.status == .ok)
                let fetched = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(fetched.taskId == createdTask.taskId)
                #expect(fetched.title == "Fetch me")
            }
        }
    }

    @Test("GET /task/{unknown-id} returns 404")
    func getUnknownTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            let unknownId = UUID()
            try await client.execute(uri: "/task/\(unknownId)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("PATCH /task/{id}/priority updates the priority")
    func updatePriority() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            let created = try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Update me","priority":3}"#)
            ) { response -> TaskItem in
                return try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
            }

            try await client.execute(
                uri: "/task/\(created.taskId)/priority",
                method: .patch,
                body: ByteBuffer(string: #"{"priority":9}"#)
            ) { response in
                #expect(response.status == .ok)
                let updated = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(updated.priority == 9)
                #expect(updated.taskId == created.taskId)
            }
        }
    }

    @Test("POST /task/{id}/cancel cancels a pending task")
    func cancelTask() async throws {
        let app = try buildTestApp()

        try await app.test(.router) { client in
            let created = try await client.execute(
                uri: "/task",
                method: .post,
                body: ByteBuffer(string: #"{"title":"Cancel me","priority":2}"#)
            ) { response -> TaskItem in
                return try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
            }

            try await client.execute(
                uri: "/task/\(created.taskId)/cancel",
                method: .post
            ) { response in
                #expect(response.status == .ok)
                let cancelled = try JSONDecoder.testDecoder.decode(TaskItem.self, from: response.body)
                #expect(cancelled.status == .cancelled)
                #expect(cancelled.taskId == created.taskId)
            }
        }
    }
}

extension JSONDecoder {
    static let testDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

## Step 14: Build and Verify

Run the full build and test suite:

```bash
swift build
swift test
```

You should see all 10 tests pass:

```
✔ Test "Create task succeeds with valid input" passed
✔ Test "Get task returns 404 when not found" passed
✔ Test "Update priority rejects values outside 1-10" passed
✔ Test "Cancel completed task returns 409 conflict" passed
✔ Test "Cancel pending task succeeds" passed
✔ Test "POST /task creates a task" passed
✔ Test "GET /task/{id} returns a previously created task" passed
✔ Test "GET /task/{unknown-id} returns 404" passed
✔ Test "PATCH /task/{id}/priority updates the priority" passed
✔ Test "POST /task/{id}/cancel cancels a pending task" passed
✔ Test run with 10 tests in 2 suites passed
```

To run subsets:

```bash
swift test --filter TaskClusterTests                # Unit tests only
swift test --filter TaskClusterIntegrationTests     # Integration tests only
```

To start the server:

```bash
swift run task-cluster
swift run task-cluster --http.host 0.0.0.0 --http.port 3000  # Custom bind
```

## What's Next

With the foundation in place, you could:

- Add list/search endpoints (`GET /task` with query parameters) -- add them to the task OpenAPI spec, then implement the new methods on `TaskController`
- Add a second API domain (e.g. billing) -- create a `BillingAPI` spec target, a `BillingController`, and register it alongside `TaskController` in `buildRouter()`
- Add a task execution engine that moves tasks from `pending` to `running` to `completed`/`failed`
- Wire up `DynamoDBTaskRepository` in the entry point for persistent storage
- Add authentication middleware using Hummingbird's `AuthRequestContext` pattern
- Generate a client SDK from the same OpenAPI spec (change `generate` to include `client`)
- Deploy to AWS with API Gateway -- the separate specs can be merged at deploy time for API Gateway import, or routes can be added programmatically in CDK
