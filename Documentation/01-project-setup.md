# Architecture and Motivations

This document introduces the architecture of task-cluster -- a cloud task management service built with Swift, Hummingbird 2.x, and swift-openapi-generator -- and explains the reasoning behind each design decision.

## What We're Building

task-cluster is a JSON API that lets clients create tasks, retrieve them by ID, update their priority, and cancel them. Tasks move through a lifecycle (`pending` -> `running` -> `completed`/`failed`/`cancelled`) and carry metadata like title, priority (1-10), and optional due dates.

The service is deliberately small in scope so that the architecture choices remain the focus rather than the business logic.

## Project Structure

```
task-cluster/
├── Package.swift                      # SPM manifest with trait-gated DynamoDB
├── openapi.yaml                       # Single OpenAPI spec (source of truth)
├── Sources/
│   ├── TaskAPI/                       # Generator config + symlink to root spec
│   │   ├── openapi.yaml → ../../openapi.yaml  # Symlink
│   │   └── openapi-generator-config.yaml      # filter: tags: [Tasks]
│   ├── TaskClusterService/            # Executable entry point
│   ├── TaskClusterApp/                # Controllers & app builder
│   │   ├── TaskController.swift       # APIProtocol conformance (task domain)
│   │   └── Application+build.swift
│   ├── TaskClusterModel/              # Domain models & repository protocol
│   └── DynamoDBTasks/                 # DynamoDB implementation (opt-in)
├── Tests/
│   ├── TaskClusterTests/              # Unit tests with Smockable mocks
│   └── TaskClusterIntegrationTests/   # Full HTTP round-trip tests
└── Documentation/
```

## Why Five Targets?

The project is split into five library/executable targets. Each split is motivated by a specific dependency boundary:

**TaskAPI** contains the generator configuration and a symlink to the root-level `openapi.yaml`. The `openapi-generator-config.yaml` uses `filter: tags: [Tasks]` to generate only the task-related operations. The `OpenAPIGenerator` build plugin runs at compile time and produces the `APIProtocol`, `Operations.*`, and `Components.Schemas.*` types. This target only depends on `OpenAPIRuntime` and has no application logic -- it's pure contract definition.

**TaskClusterModel** has no web framework dependency. It defines the domain types (`TaskItem`, `TaskStatus`), the storage protocol (`TaskRepository`), and the in-memory implementation. Because it only depends on Foundation and Smockable, it can be reused in CLI tools, Lambda functions, or other contexts without pulling in Hummingbird.

**TaskClusterApp** depends on Hummingbird, TaskAPI, TaskClusterModel, OpenAPIRuntime, and OpenAPIHummingbird. It contains controllers that conform to `APIProtocol` (one per API domain) and the `buildApplication()` function. Currently there is one controller -- `TaskController` -- which implements the task management API. It knows *how* to handle HTTP but doesn't know *which* repository it's talking to -- that's injected as a generic parameter.

**TaskClusterService** is the executable. It makes the concrete decision to use `InMemoryTaskRepository`, reads configuration via `swift-configuration`'s `ConfigReader`, and starts the server. This is the only target that "knows" the full picture.

**DynamoDBTasks** depends on TaskClusterModel and (conditionally) on dynamo-db-tables. It provides an alternative `TaskRepository` implementation. Because it's a separate target gated behind an SPM trait, developers who don't need DynamoDB never download or compile the AWS SDK.

This layering means:
- The API contract is explicit and drives the server code
- The domain model is portable and test-friendly
- The HTTP layer is testable with any repository (mocks or in-memory)
- Storage backends are swappable without touching route handlers
- Heavy dependencies like the AWS SDK are opt-in

## Why Hummingbird?

Hummingbird 2.x is a lightweight, modular Swift server framework with a few characteristics that suit this project:

- **Generic request context.** Handlers receive a typed `Context` alongside the `Request`. The framework provides `BasicRequestContext` as a sensible default, and you can define custom contexts when you need middleware to enrich requests with authentication state or tracing data.

- **OpenAPI integration.** The `swift-openapi-hummingbird` package makes Hummingbird's `Router` conform to `ServerTransport`, so generated `APIProtocol` implementations can register their handlers directly on the router with `api.registerHandlers(on: router)`.

- **`buildApplication()` pattern.** The idiomatic Hummingbird setup is a function that creates a `Router`, adds middleware, wires the API implementation, and returns `some ApplicationProtocol`. The official Hummingbird template follows this pattern.

- **Testing without HTTP.** `HummingbirdTesting` provides a `.router` transport that runs requests through the router in-process, without binding a port. Tests are fast and deterministic.

## Why OpenAPI-Driven Development?

The API contract lives in `openapi.yaml` at the project root and is the single source of truth for the HTTP interface. The `swift-openapi-generator` build plugin reads this spec at compile time and generates:

- **`APIProtocol`** -- a Swift protocol with one method per `operationId` in the spec. Your server code conforms to this protocol.
- **`Operations.*`** -- namespaced types for each operation's `Input` and `Output`, with type-safe representations of path parameters, request bodies, and response status codes.
- **`Components.Schemas.*`** -- Swift structs and enums for every schema defined in `components/schemas`.

This approach has several benefits over hand-written controllers:

1. **The spec drives the code.** Adding an endpoint means adding it to the OpenAPI spec first. The compiler then tells you which method to implement. You can't accidentally diverge from the contract.

2. **Type-safe status codes.** Each response status code in the spec becomes a case on the output enum (`.created`, `.notFound`, `.conflict`). You can't return a 409 from an endpoint that only declares 200 and 404.

3. **No manual route registration.** Routes are generated from the spec's paths. `api.registerHandlers(on: router)` registers everything automatically.

4. **Request/response types are generated.** You don't write `CreateTaskRequest` or `TaskResponse` structs by hand -- they come from `Components.Schemas.*`.

The mapping from spec to code:

| OpenAPI operationId | HTTP | Controller method |
|---|---|---|
| `createTask` | `POST /task` | `TaskController.createTask(_:)` |
| `getTask` | `GET /task/{taskId}` | `TaskController.getTask(_:)` |
| `updateTaskPriority` | `PATCH /task/{taskId}/priority` | `TaskController.updateTaskPriority(_:)` |
| `cancelTask` | `POST /task/{taskId}/cancel` | `TaskController.cancelTask(_:)` |

## Single Spec, Tag-Based Filtering

A single `openapi.yaml` at the project root is the source of truth for the entire API. Each API domain gets its own target that symlinks to this root spec and uses `filter` in `openapi-generator-config.yaml` to generate only its subset of operations by tag. Currently the project has one domain (tasks), but this pattern scales to multiple domains by adding more API targets:

```
task-cluster/
├── openapi.yaml                      # Single spec (all domains, all operations)
└── Sources/
    ├── TaskAPI/                       # Task domain: filter by tag "Tasks"
    │   ├── openapi.yaml → ../../openapi.yaml
    │   └── openapi-generator-config.yaml
    ├── BillingAPI/                    # (future) Billing domain: filter by tag "Billing"
    │   ├── openapi.yaml → ../../openapi.yaml
    │   └── openapi-generator-config.yaml
    └── TaskClusterApp/
        ├── TaskController.swift      # conforms to TaskAPI.APIProtocol
        ├── BillingController.swift   # (future) conforms to BillingAPI.APIProtocol
        └── Application+build.swift   # calls registerHandlers for each controller
```

In `buildRouter()`, each controller registers its handlers on the same router:

```swift
let taskController = TaskController(repository: repository)
try taskController.registerHandlers(on: router)

// Future:
// let billingController = BillingController(billingService: billing)
// try billingController.registerHandlers(on: router)
```

Paths can't collide across specs, but that's enforced naturally by giving each domain its own path prefix (`/task/*`, `/invoice/*`, etc.). For AWS deployment, the specs can be merged at deploy time for API Gateway import, or routes can be added programmatically in CDK -- the service process itself serves the unified API regardless.

## The Repository Pattern

`TaskRepository` is a protocol with three methods: `create`, `get`, and `update`. The `TaskController` is generic over `<Repository: TaskRepository>`, so it works with any implementation.

This gives us three interchangeable backends:

1. **InMemoryTaskRepository** -- An actor with a `[UUID: TaskItem]` dictionary. Used for local development and integration tests. Zero configuration, zero latency.

2. **MockTaskRepository** -- Generated at compile time by the `@Smock` macro. Used in unit tests to control exactly what the repository returns, without needing any real storage.

3. **DynamoDBTaskRepository** -- Uses composite primary keys (`TASK` / `TASK#<uuid>`) and optimistic locking via `StandardTypedDatabaseItem`. Only compiled when the `DynamoDB` trait is active.

The protocol lives in TaskClusterModel alongside its in-memory implementation. This means the model target is self-contained -- you can build and test it without any other targets.

## Smockable for Testing

The `@Smock` macro on the `TaskRepository` protocol generates a `MockTaskRepository` class at compile time. In unit tests, you configure expectations before each test:

```swift
var expectations = MockTaskRepository.Expectations()
when(expectations.get(taskId: .any), return: someTask)
let mock = MockTaskRepository(expectations: expectations)
```

This is more capable than a hand-written mock because:
- `.any` matches any argument value
- `use:` closures let you compute return values dynamically
- `verify()` can assert how many times a method was called

The key benefit is that unit tests for the controller don't depend on any repository implementation -- they test the handler logic (validation, status transitions, error codes) in complete isolation.

## SPM Traits (SE-0450)

The `DynamoDB` trait in `Package.swift` makes the dynamo-db-tables dependency optional:

```swift
traits: [
    "DynamoDB",
],
```

The dependency is always *listed* in `Package.swift` (SPM requires this), but it's only *linked* when the trait is active, via a conditional target dependency:

```swift
.product(name: "DynamoDBTables", package: "dynamo-db-tables",
         condition: .when(traits: ["DynamoDB"]))
```

In source code, the entire DynamoDB implementation is wrapped in `#if DynamoDB`:

```swift
#if DynamoDB
import DynamoDBTables
// ... implementation ...
#endif
```

The practical benefit: `swift build` is fast and downloads only Hummingbird, the OpenAPI packages, and Smockable. The AWS SDK (and its transitive dependencies) only appear when you explicitly opt in with `swift build --traits DynamoDB`.

## Two Layers of Tests

The project has two test targets that serve different purposes:

**TaskClusterTests (unit tests)** use `MockTaskRepository` to test controller logic in isolation. Each test configures the mock to return specific data, then sends a request through `app.test(.router)` and asserts on the response status and body. These tests answer questions like "does the handler return 409 when cancelling a completed task?"

**TaskClusterIntegrationTests** use `InMemoryTaskRepository` with the same `.router` transport. These tests exercise the full stack -- routing, OpenAPI deserialization, handler logic, repository storage, OpenAPI serialization -- in a single round trip. They answer questions like "can I create a task and then fetch it back by ID?"

Both test targets use Swift Testing (`import Testing`) with `@Test` and `#expect`, and both use HummingbirdTesting's `.router` transport so they run in-process without binding a network port.
