// swift-tools-version:5.6
import PackageDescription

let package = Package(
	name: "swiftarr",
	platforms: [
		.macOS(.v12)
	],
	products: [
		.library(name: "swiftarr", targets: ["App"])
	],
	dependencies: [
		.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
		.package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/leaf.git", from: "4.0.0"),
		.package(url: "https://github.com/MrLotU/SwiftPrometheus.git", from: "1.0.0-alpha"),
		.package(url: "https://github.com/johnsundell/ink.git", from: "0.1.0"),
	],
	targets: [
		.systemLibrary(name: "gd", pkgConfig: "gdlib", providers: [.apt(["libgd-dev"]), .brew(["gd"])]),
		.systemLibrary(name: "jpeg", pkgConfig: "libjpeg", providers: [.apt(["libjpeg-dev"]), .brew(["jpeg"])]),
		.target(name: "gdOverrides", dependencies: ["gd", "jpeg"], publicHeadersPath: "."),
		.target(
			name: "App",
			dependencies: [
				"gd",
				"jpeg",
				"gdOverrides",
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
				.product(name: "Vapor", package: "vapor"),
				.product(name: "Redis", package: "redis"),
				.product(name: "Leaf", package: "leaf"),
				.product(name: "SwiftPrometheus", package: "SwiftPrometheus"),
				.product(name: "Ink", package: "ink"),
			],
			resources: [
				.copy("Resources"),
				.copy("seeds"),
			]
		),
		.executableTarget(name: "Run", dependencies: ["App"]),
		.testTarget(name: "AppTests", dependencies: ["App"]),
	],
	cLanguageStandard: .c11
)
