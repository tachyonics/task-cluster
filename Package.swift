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
        .default(enabledTraits: ["DynamoDB"]),
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
        // MARK: - Generated API types from OpenAPI spec
        .target(
            name: "TaskAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),

        // MARK: - Core domain models and repository protocol
        .target(
            name: "TaskClusterModel",
            dependencies: [
                .product(name: "Smockable", package: "smockable"),
            ]
        ),

        // MARK: - Hummingbird app layer (APIProtocol implementation, app builder)
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

        // MARK: - Executable entry point
        .executableTarget(
            name: "TaskClusterService",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterModel",
                .product(name: "Configuration", package: "swift-configuration"),
            ]
        ),

        // MARK: - DynamoDB implementation (trait-gated)
        .target(
            name: "DynamoDBTasks",
            dependencies: [
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables", condition: .when(traits: ["DynamoDB"])),
            ]
        ),

        // MARK: - Unit tests (Smockable mocks)
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

        // MARK: - Integration tests (HummingbirdTesting)
        .testTarget(
            name: "TaskClusterIntegrationTests",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterModel",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),

        // MARK: - DynamoDB repository tests (trait-gated)
        .testTarget(
            name: "DynamoDBTasksTests",
            dependencies: [
                "DynamoDBTasks",
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables",
                         condition: .when(traits: ["DynamoDB"])),
            ]
        ),
    ]
)
