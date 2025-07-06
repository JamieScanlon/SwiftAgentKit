// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "A2AFoundation",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "A2AFoundation",
            targets: ["A2AFoundation"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/JamieScanlon/EasyJSON.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "A2AFoundation",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "EasyJSON", package: "EasyJSON"),
            ]),
        .testTarget(
            name: "A2AFoundationTests",
            dependencies: ["A2AFoundation"]
        ),
    ]
)
