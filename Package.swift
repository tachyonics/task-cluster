// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "task-cluster",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/dynamo-db-tables", from: "1.0.0-rc.2"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-hummingbird", from: "2.0.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(url: "https://github.com/tachyonics/smockable", from: "1.0.0-rc.3"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.1.0"),
        .package(url: "https://github.com/tachyonics/swift-wire", branch: "main"),
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
                "TaskClusterModel",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
            ]
        ),
        .executableTarget(
            name: "TaskCluster",
            dependencies: [
                "TaskClusterApp",
                "TaskClusterDynamoDBModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Wire", package: "swift-wire"),
            ],
            plugins: [.plugin(name: "WireBuildPlugin", package: "swift-wire")]
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
            name: "TaskClusterDynamoDBModelTests",
            dependencies: [
                "TaskClusterDynamoDBModel",
                "TaskClusterModel",
                .product(name: "DynamoDBTables", package: "dynamo-db-tables"),
            ]
        ),
    ]
)
