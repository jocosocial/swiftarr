// swift-tools-version:5.8
import PackageDescription

let package = Package(
	name: "swiftarr",
	platforms: [
		.macOS(.v12)
	],
	dependencies: [
		.package(url: "https://github.com/vapor/vapor.git", from: "4.76.0"),
		.package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
		.package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/leaf.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.0.0"),
		.package(url: "https://github.com/MrLotU/SwiftPrometheus.git", from: "1.0.0-alpha"),
		.package(url: "https://github.com/johnsundell/ink.git", from: "0.1.0"),
	],
	targets: [
		.systemLibrary(name: "gd", pkgConfig: "gdlib", providers: [.apt(["libgd-dev"]), .brew(["gd"]), .yum(["gd-devel"])]),
		.systemLibrary(name: "jpeg", pkgConfig: "libjpeg", providers: [.apt(["libjpeg-dev"]), .brew(["jpeg-turbo"]), .yum(["libjpeg-turbo-devel"])]),
		.target(name: "gdOverrides", dependencies: ["gd", "jpeg"], publicHeadersPath: "."),
        .executableTarget(
            name: "swiftarr",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
				.product(name: "Redis", package: "redis"),
				.product(name: "Leaf", package: "leaf"),
				.product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
				.product(name: "SwiftPrometheus", package: "SwiftPrometheus"),
				.product(name: "Ink", package: "ink"),
				"gd",
				"jpeg",
				"gdOverrides",
            ],
			resources: [
				.copy("Resources"),
				.copy("seeds"),
			]
        ),
		.testTarget(name: "AppTests", dependencies: ["swiftarr"]),
	],
	cLanguageStandard: .c11
)
