// swift-tools-version:5.10
import PackageDescription

let package = Package(
	name: "swiftarr",
	platforms: [
		.macOS(.v13)
	],
	dependencies: [
		.package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
		.package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
		.package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
		.package(url: "https://github.com/vapor/leaf.git", from: "4.3.0"),
		.package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.1.1"),
		.package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0-alpha"),
		.package(url: "https://github.com/johnsundell/ink.git", from: "0.6.0"),
	],
	targets: [
		.systemLibrary(name: "gd", pkgConfig: "gdlib", providers: [.apt(["libgd-dev"]), .brew(["gd"]), .yum(["gd-devel"])]),
		.systemLibrary(name: "jpeg", pkgConfig: "libjpeg", providers: [.apt(["libjpeg-dev"]), .brew(["jpeg-turbo"]), .yum(["libjpeg-turbo-devel"])]),
		.target(name: "gdOverrides", dependencies: ["gd", "jpeg"], publicHeadersPath: "."),
		.executableTarget(
			name: "swiftarr",
			dependencies: [
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
				.product(name: "Redis", package: "redis"),
				.product(name: "Leaf", package: "leaf"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
				.product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
				.product(name: "Prometheus", package: "swift-prometheus"),
				.product(name: "Ink", package: "ink"),
				"gd",
				"jpeg",
				"gdOverrides",
			],
			resources: [
				.copy("Resources"),
				.copy("seeds"),
			],
            swiftSettings: swiftSettings
		),
		.testTarget(
			name: "AppTests", 
			dependencies: [
				.target(name: "swiftarr"),
				.product(name: "XCTVapor", package: "vapor")
			],
			swiftSettings: swiftSettings
		)
	],
	cLanguageStandard: .c11
)

var swiftSettings: [SwiftSetting] { [
	.enableUpcomingFeature("DisableOutwardActorInference"),
//	.enableExperimentalFeature("StrictConcurrency"),
//	.unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"])
//	.unsafeFlags(["-Xfrontend", "-warn-concurrency"])
] }
