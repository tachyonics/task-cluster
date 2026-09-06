// swift-tools-version: 6.4
// 6.4 and macOS 26, raised from 6.2/v15 by the M6d port. WireOpenAPI mounts operations as WireMVC routes,
// and WireMVC's core is proposal-native — it dispatches over swift-http-api-proposal's HTTPServer, whose
// `~Copyable` / `consuming sending` streaming types set that floor. Not an incidental bump: it is the cost
// of operations and `@Get` routes being the same kind of thing.
//
// **This package now serves on that proposal server directly.** Hummingbird, swift-openapi-hummingbird and
// `WireMVCServerTransport` are gone: the composition root is a `@WireMVCBootstrap` type that hands the
// generated entry point an `NIOHTTPServer` and a `TrieRouteBuilder`, and the collated route contributors —
// the OpenAPI operations and the `@Get` health route alike — are registered onto that one builder. The
// ServerTransport adapter existed to carry them onto a *host framework's* router; with no host framework
// there is nothing left for it to bridge.

import PackageDescription

// The flag set wire-mvc and wire-open-api compile their own API with. The proposal's API is compiled with
// them, so a consumer naming its types — which the composition root does, in `createRouteBuilder(for:)` and
// the `@NotFound` handler's `consuming sending Sender` — needs the same. Kept as a whole rather than
// trimmed to what today's sources happen to need: the point is to agree with the packages this one calls,
// and a subset silently disagrees the moment a signature moves.
//
// One deliberate omission — `InternalImportsByDefault`, which wire-mvc's own list carries. It is the one
// flag that is *not* about agreeing with a caller: it constrains how this package's own modules import,
// and these modules hold `package` declarations whose signatures name `Foundation` and `TaskAPI` types.
// This is the same split wire-open-api's fixtures make for the module holding generated public API.
let proposalSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("LifetimeDependence"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "task-cluster",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-server-community/dynamo-db-tables",
            from: "1.0.0-rc.4",
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
        .package(url: "https://github.com/tachyonics/smockable", from: "1.0.0-rc.5"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.1.0"),
        // The wire packages moved to their own GitHub organisation. The old `tachyonics/…` URLs still
        // redirect, but a redirect is not an identity: SwiftPM keys a dependency by URL, so a graph where
        // one package names the old host and another names the new resolves them as two packages.
        // wire-mvc and wire-open-api already name each other at `swift-wire/…`, which makes this the only
        // spelling that resolves to one copy.
        .package(url: "https://github.com/swift-wire/swift-wire.git", branch: "main"),
        .package(url: "https://github.com/swift-wire/wire-open-api.git", branch: "main"),
        // `NIOHTTPServer` is the trait that matters here: it is what lets `WireMVCTesting` stand a suite up
        // on a real loopback server, and it gates the `swift-http-server` dependency so a consumer that
        // does not serve on NIO resolves no NIO stack. `ServerTransport` is *not* requested — nothing here
        // bridges onto a host framework any more — but it arrives anyway, because wire-open-api asks for it
        // unconditionally and SwiftPM unions traits across the graph.
        .package(
            url: "https://github.com/swift-wire/wire-mvc.git",
            branch: "main",
            traits: [.defaults, "NIOHTTPServer"]
        ),
        // The proposal itself, and the concrete server this app serves on. Both are named directly rather
        // than reached through wire-mvc: the composition root writes `some HTTPServer` and returns a
        // concrete `NIOHTTPServer`, so they are this package's own API surface, not an implementation
        // detail of the adapter.
        .package(url: "https://github.com/apple/swift-http-api-proposal.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/swift-server/swift-http-server.git", branch: "main"),
        // `UniqueArray`, the buffer the `@NotFound` handler writes its body from.
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.13.2"),
        .package(url: "https://github.com/tachyonics/swift-local-containers", from: "0.9.2"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.24.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.0.0"),
    ],
    targets: [
        // The domain types. It declares no bindings and imports nothing from Wire — but the graph *names*
        // `TaskRepository` (the constraint `TaskController` is generic over, and the key
        // `DynamoDBTaskRepository` binds), so the generated code has to be able to import this module.
        // Under the retired `_WireExports.swift` marker that came from the marker file; the predicate that
        // replaced it is this dependency. Without it the emitted handlers fail with
        // "cannot find type 'TaskRepository' in scope".
        .target(
            name: "TaskClusterModel",
            dependencies: [
                .product(name: "Wire", package: "swift-wire")
            ]
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
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                // Not imported by anything here — this target is generated types and nothing else. It is
                // how the module is *discovered*: swift-wire retired the `_WireExports.swift` marker in
                // favour of "declares a dependency on the `Wire` product", and WireOpenAPIGen reuses that
                // predicate to decide which dependency modules it will look for an OpenAPI document in.
                // Without it `@OpenAPIController(spec: "TaskAPI")` resolves to nothing and the build fails
                // saying no dependency carries a document.
                .product(name: "Wire", package: "swift-wire"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "TaskClusterApp",
            dependencies: [
                "TaskAPI",
                "TaskClusterModel",
                .product(name: "WireMVC", package: "wire-mvc"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
            ],
            swiftSettings: proposalSettings
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
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
                .product(name: "WireMVC", package: "wire-mvc"),
                // The batteries-included native router: `TrieRouteBuilder`, the
                // `FinalizableHTTPServerRouteBuilder` the composition root hands back, which the generated
                // entry point freezes into the router it serves.
                .product(name: "WireMVCRouter", package: "wire-mvc"),
                .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
                .product(name: "NIOHTTPServer", package: "swift-http-server"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
                // The generated entry point hands the graph's collated services to `WireMVC.serve`, so
                // `Service` is named in this module's own compiled code.
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: proposalSettings,
            // Three plugins, none knowing about another: WireBuildPlugin emits the graph exactly once,
            // then each adapter contributes its own domain generator. The bundled per-adapter plugins
            // cannot express this — applying one silently leaves the other's witnesses ungenerated.
            // WireMVCRouteGen is also what emits the `@main` for this target's `@WireMVCBootstrap`
            // composition root, which is why there is no `main.swift` here.
            plugins: [
                .plugin(name: "WireBuildPlugin", package: "swift-wire"),
                .plugin(name: "WireMVCRouteGenPlugin", package: "wire-mvc"),
                .plugin(name: "WireOpenAPIGenPlugin", package: "wire-open-api"),
            ]
        ),
        .testTarget(
            name: "TaskClusterTests",
            dependencies: [
                // The **executable**, not just the app library: the `@WireMVCBootstrap` composition root
                // lives there, and it is what the generated `.wiremvc(_:)` suite trait stands up. Depending
                // on `TaskClusterApp` alone would re-compose a graph with no composition root in it.
                "TaskCluster",
                "TaskClusterApp",
                "TaskClusterModel",
                // The real `TaskRepository` binding lives here. `@BindType` *supersedes* a slot rather than
                // inventing one, so the binding it replaces has to be in the re-composed graph — composition
                // scans a target's own direct dependencies, and reaching this only through `TaskCluster`
                // leaves it out. Its production chain is then pruned, because nothing under the variant
                // reaches it.
                "TaskClusterDynamoDBModel",
                "TaskAPI",
                .product(name: "Smockable", package: "smockable"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireTesting", package: "swift-wire"),
                .product(name: "WireMVC", package: "wire-mvc"),
                .product(name: "WireMVCTesting", package: "wire-mvc"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
            ],
            swiftSettings: proposalSettings,
            // The same three plugins the executable applies. This target re-composes the app's graph —
            // its `@BindType` variant supersedes the repository binding with a test double — and a
            // contributor proxy is generated per target, so the test module needs its own.
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
        // service against a real table — exercising the live AWS client. Gated on a
        // container runtime + LocalStack token, so it skips where those aren't available.
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
