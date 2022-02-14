// swift-tools-version:5.5
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
            name: "SwiftUIGraphQLCodegen",
            targets: ["CodegenExecutable"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", revision: "b2975c4"),
//        .package(url: "https://github.com/GraphQLSwift/GraphQL.git", from: "2.1.2"),
        .package(name: "GraphQL", path: "/Users/luke/Source/graphql-swift"),
        .package(name: "SwiftSyntax", url: "https://github.com/apple/swift-syntax.git", .exact("0.50500.0")),
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
            dependencies: ["SwiftUIGraphQL"]),
        .target(name: "Codegen", dependencies: [
            "SwiftUIGraphQL",
            "SwiftSyntax",
            .product(name: "SwiftSyntaxBuilder", package: "SwiftSyntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "GraphQL", package: "GraphQL"),
            .product(name: "Collections", package: "swift-collections")
        ]),
        .executableTarget(name: "CodegenExecutable", dependencies: ["Codegen"]),
        .testTarget(
            name: "CodegenTests",
            dependencies: ["Codegen"],
            resources: [Resource.copy("Cases")]
        )
    ]
)
