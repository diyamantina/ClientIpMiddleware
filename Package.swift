// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClientIpMiddleware",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClientIpMiddleware",
            targets: ["ClientIpMiddleware"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor", from: "4.119.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
    ],
    targets: [
        .target(
            name: "ClientIpMiddleware",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .testTarget(
            name: "ClientIpMiddlewareTests",
            dependencies: [
                "ClientIpMiddleware",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporTesting", package: "vapor")
            ]
        )
    ]
)
