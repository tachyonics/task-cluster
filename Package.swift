// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "task-cluster",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/dynamo-db-tables", from: "0.1.0")
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
        .executableTarget(
            name: "task-cluster"
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
