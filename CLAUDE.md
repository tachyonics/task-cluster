# task-cluster

Cloud task management service built with Hummingbird 2.x and swift-openapi-generator.

## Build & Run

```bash
swift build                              # Build (in-memory only)
swift build --traits DynamoDB            # Build with DynamoDB support
swift run task-cluster                   # Run on localhost:8080
swift run task-cluster --http.host 0.0.0.0 --http.port 3000  # Custom bind
```

## Test

```bash
swift test                                          # All tests
swift test --filter TaskClusterTests                # Unit tests only
swift test --filter TaskClusterIntegrationTests     # Integration tests only
```

## Architecture

- **TaskAPI** -- OpenAPI generator config + symlink to the root `openapi.yaml`. Uses `filter: tags: [Tasks]` to generate only task operations. The `OpenAPIGenerator` build plugin produces `APIProtocol`, `Operations.*`, and `Components.Schemas.*` at compile time
- **TaskClusterModel** -- Domain types (`TaskItem`, `TaskStatus`), `TaskRepository` protocol (with `@Smock` macro for mocking), and `InMemoryTaskRepository` actor
- **TaskClusterApp** -- `APIProtocol` conformance (`TaskController`), `buildApplication()` wiring. Each API domain gets its own spec target and controller; `buildRouter()` calls `registerHandlers(on:)` for each
- **TaskClusterService** -- `@main` executable entry point using `swift-configuration` (`ConfigReader`)
- **DynamoDBTasks** -- DynamoDB `TaskRepository` implementation, gated behind the `DynamoDB` SPM trait (SE-0450)

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/task` | POST | Create task |
| `/task/{taskId}` | GET | Get task by ID |
| `/task/{taskId}/priority` | PATCH | Update priority |
| `/task/{taskId}/cancel` | POST | Cancel task |

## Key Patterns

- **OpenAPI-driven** -- The spec at `./openapi.yaml` (project root) is the single source of truth. Each API target (e.g. `Sources/TaskAPI/`) symlinks to it and uses `filter` in `openapi-generator-config.yaml` to generate only its subset of operations by tag. The build plugin generates type-safe server stubs (`APIProtocol`) and request/response types
- **Repository protocol** -- All storage goes through `TaskRepository`. Swap implementations via DI
- **Smockable mocks** -- `@Smock` generates `MockTaskRepository` for unit tests
- **SPM traits** -- `DynamoDB` trait gates the dynamo-db-tables dependency so it's not fetched unless needed
