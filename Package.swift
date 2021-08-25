// swift-tools-version:5.2
import PackageDescription

let package = Package(
	name: "swiftarr",
	platforms: [
		.macOS(.v10_15),
	],
	products: [
		.library(name: "swiftarr", targets: ["App"]),
	],
	dependencies: [
		.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
		.package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/leaf.git", from: "4.0.0"),
	],
	targets: [
        .systemLibrary(name: "gd", pkgConfig: "gdlib", providers: [.apt(["libgd-dev"]), .brew(["gd"])]),
		.target(name: "App", dependencies: ["gd",
											.product(name: "Fluent", package: "fluent"),
											.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
											.product(name: "Vapor", package: "vapor"),
											.product(name: "Redis", package: "redis"),
											.product(name: "Leaf", package: "leaf"),
											]),
		.target(name: "Run", dependencies: ["App"]),
		.testTarget(name: "AppTests", dependencies: ["App"])
	]
)
