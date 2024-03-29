// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swiftui-graphql",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftUIGraphQL",
            targets: ["SwiftUIGraphQL"]),
        .executable(
            name: "swiftui-graphql-codegen",
            targets: ["swiftui-graphql-codegen"]
        ),
        .executable(
            name: "swiftui-graphql-download-schema",
            targets: ["swiftui-graphql-download-schema"]
        ),
        .plugin(name: "SwiftUIGraphQLCodegenPlugin", targets: ["CodegenPlugin"]),
        .plugin(name: "SwiftUIGraphQLDownloadSchemaPlugin", targets: ["DownloadSchemaPlugin"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.1"),
        .package(url: "https://github.com/minm-inc/GraphQL", revision: "a3530565b58b1688abddd868ddf053eb8fb54f40"),
//        .package(path: "~/Source/graphql-swift"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "0.50500.0"),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            .upToNextMajor(from: "1.0.0")
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SwiftUIGraphQL",
            dependencies: []),
        .testTarget(
            name: "SwiftUIGraphQLTests",
            dependencies: [
                "SwiftUIGraphQL",
                "Codegen",
                .product(name: "GraphQL", package: "GraphQL"),
            ],
            resources: [.copy("fooResponse.json")]
        ),
        .target(name: "Codegen", dependencies: [
            "SwiftUIGraphQL",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "GraphQL", package: "GraphQL"),
            .product(name: "OrderedCollections", package: "swift-collections")
        ]),
        .executableTarget(name: "swiftui-graphql-codegen", dependencies: ["Codegen"]),
        .testTarget(
            name: "CodegenTests",
            dependencies: ["Codegen"],
            resources: [Resource.copy("Cases")]
        ),
        .plugin(
            name: "CodegenPlugin",
            capability: .buildTool(),
            dependencies: ["swiftui-graphql-codegen"]
        ),
        .executableTarget(name: "swiftui-graphql-download-schema", dependencies: [
            "SwiftUIGraphQL",
            .product(name: "GraphQL", package: "GraphQL"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .plugin(
            name: "DownloadSchemaPlugin",
            capability: .command(
                intent: .custom(verb: "download-schema", description: "Downloads the graphql schema"),
                permissions: [.writeToPackageDirectory(reason: "To write the downloaded schema.json")]
            ),
            dependencies: ["swiftui-graphql-download-schema"]
        )
    ]
)
