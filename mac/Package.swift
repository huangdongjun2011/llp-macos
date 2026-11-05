// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LLP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LLP", targets: ["LLP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.0.0")
    ],
    targets: [
        .plugin(
            name: "ValidatedOpenAPIGenerator",
            capability: .buildTool(),
            dependencies: [.product(name: "swift-openapi-generator", package: "swift-openapi-generator")]
        ),
        .target(
            name: "LLPGenerated",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types")
            ],
            path: "Sources/LLPApis",
            exclude: ["openapi-generator-config.yaml"],
            plugins: [.plugin(name: "ValidatedOpenAPIGenerator")]
        ),
        .target(
            name: "LLPCore",
            dependencies: [
                "LLPGenerated",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/LLPCore"
        ),
        .executableTarget(
            name: "LLP",
            dependencies: ["LLPCore", "LLPGenerated"],
            path: "Sources/LLP"
        ),
        .testTarget(
            name: "LLPTests",
            dependencies: ["LLP", "LLPCore", "LLPGenerated"],
            path: "Tests/LLPTests"
        )
    ]
)
