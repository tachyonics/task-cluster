// swift-tools-version: 6.4
// 6.4 and macOS 26, raised from 6.2/v15 by the M6d port. WireOpenAPI now mounts operations as WireMVC
// routes, and WireMVC's core is proposal-native — it dispatches over swift-http-api-proposal's
// HTTPServer, whose `~Copyable` / `consuming sending` streaming types set that floor. Not an incidental
// bump: it is the cost of operations and `@Get` routes being the same kind of thing.

import PackageDescription

let package = Package(
    name: "task-cluster",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-server-community/dynamo-db-tables",
            from: "1.0.0-rc.3",
            traits: ["SOTOSDK"]
        ),
        .package(url: "https://github.com/soto-project/soto", from: "7.0.0"),
        .package(url: "https://github.com/soto-project/soto-core", from: "7.0.0"),
        // **A fork, pinned to a revision.** WireOpenAPI dispatches each operation individually by
        // calling the generated per-operation method on `UniversalServer`, which stock
        // swift-openapi-generator emits `fileprivate`; the fork lets it follow the configured access
        // modifier. Pinned rather than tracked by branch so generated code cannot change underneath.
        // Points back at the released package once upstream takes it.
        .package(
            url: "https://github.com/tachyonics/swift-openapi-generator.git",
            revision: "9e655e0adb9b993ef4cb29a6aa0dfc59b9b42b09"
        ),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-hummingbird", from: "2.0.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(url: "https://github.com/tachyonics/smockable", from: "1.0.0-rc.5"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.1.0"),
        .package(url: "https://github.com/tachyonics/swift-wire", branch: "main"),
        .package(url: "https://github.com/tachyonics/wire-open-api", branch: "main"),
        // Operations are WireMVC routes now, so wire-mvc is a direct dependency. The `ServerTransport`
        // trait pulls in the adapter that carries them onto Hummingbird's `Router`.
        .package(url: "https://github.com/tachyonics/wire-mvc", branch: "main", traits: ["ServerTransport"]),
        .package(url: "https://github.com/tachyonics/swift-local-containers", from: "0.9.2"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.24.0"),
        // The graph-teardown service lives here now rather than in an adapter, so its one dependency
        // is named directly.
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "TaskClusterModel"
        ),
        .target(
            name: "TaskClusterDynamoDBModel",
            dependencies: [
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables"),
                .product(name: "Wire", package: "swift-wire"),
            ]
        ),
        .target(
            name: "TaskAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "TaskClusterApp",
            dependencies: [
                "TaskAPI",
                .product(name: "WireMVC", package: "wire-mvc"),
                // `Application+build.swift` lives here and imports it: this target owns the call to
                // `WireMVCServerTransport.apply`, so it declares the dependency rather than relying on
                // reaching it through the executable.
                .product(name: "WireMVCServerTransport", package: "wire-mvc"),
                // `GraphTeardownService` is declared in this target, so `Service` is this target's
                // dependency — it was reaching it through the executable, which Linux does not allow.
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                "TaskClusterModel",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
            ]
        ),
        .executableTarget(
            name: "TaskCluster",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterDynamoDBModel",
                // Direct dependencies because the OpenAPI codegen plugin walks *this* target's own:
                // TaskAPI so its document is read, TaskClusterModel so the emitted conformer can name
                // `TaskRepository`, the constraint TaskController is generic over. Reaching either only
                // transitively through TaskClusterApp leaves them invisible to the plugin.
                "TaskAPI",
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables"),
                .product(name: "DynamoDBTablesSoto", package: "dynamo-db-tables"),
                .product(name: "SotoCore", package: "soto-core"),
                .product(name: "SotoDynamoDB", package: "soto"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
                .product(name: "WireMVC", package: "wire-mvc"),
                .product(name: "WireMVCServerTransport", package: "wire-mvc"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            // Three plugins, none knowing about another: WireBuildPlugin emits the graph exactly once,
            // then each adapter contributes its own domain generator. The bundled per-adapter plugins
            // cannot express this — applying one silently leaves the other's witnesses ungenerated.
            plugins: [
                .plugin(name: "WireBuildPlugin", package: "swift-wire"),
                .plugin(name: "WireMVCRouteGenPlugin", package: "wire-mvc"),
                .plugin(name: "WireOpenAPIGenPlugin", package: "wire-open-api"),
            ]
        ),
        .testTarget(
            name: "TaskClusterTests",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterModel",
                "TaskAPI",
                .product(name: "Smockable", package: "smockable"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
                .product(name: "WireMVC", package: "wire-mvc"),
                // `buildApplication` calls into it, so the test binary has to link it too.
                .product(name: "WireMVCServerTransport", package: "wire-mvc"),
                // `TestGraph.services` is typed `[any Service]`.
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Wire", package: "swift-wire"),
            ],
            // The same three plugins the executable applies. These tests hand-build a graph around a
            // mocked repository rather than bootstrapping one, and the thing a graph now supplies is a
            // `RouteContributor` — the proxy WireGen synthesises and WireOpenAPIGen gives its
            // conformances. A proxy is generated per target, so the test module needs its own; without
            // the plugins there is no type to put in the graph.
            plugins: [
                .plugin(name: "WireBuildPlugin", package: "swift-wire"),
                .plugin(name: "WireMVCRouteGenPlugin", package: "wire-mvc"),
                .plugin(name: "WireOpenAPIGenPlugin", package: "wire-open-api"),
            ]
        ),
        .testTarget(
            name: "TaskClusterDynamoDBModelTests",
            dependencies: [
                "TaskClusterDynamoDBModel",
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables"),
            ]
        ),
        // LocalStack integration: builds TaskCluster from the package-root Dockerfile,
        // stands up a LocalStack DynamoDB (the table codegen'd from
        // Resources/dynamodb-table.json), and round-trips a task through the running
        // service against a real table — exercising the live AWS client (and its
        // @Teardown shutdown when the container stops). Gated on a container runtime +
        // LocalStack token, so it skips where those aren't available.
        .testTarget(
            name: "TaskClusterIntegrationTests",
            dependencies: [
                .product(name: "ContainerMacrosLib", package: "swift-local-containers"),
                .product(name: "ContainerTestSupport", package: "swift-local-containers"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            plugins: [
                .plugin(name: "ContainerCodeGen", package: "swift-local-containers")
            ]
        ),
    ]
)
