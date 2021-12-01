// swift-tools-version:5.5
import PackageDescription

let package = Package(
	name: "swiftarr",
	platforms: [
		.macOS(.v12),
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
        .package(url: "https://github.com/MrLotU/SwiftPrometheus.git", from: "1.0.0-alpha")
	],
	targets: [
        .systemLibrary(name: "gd", pkgConfig: "gdlib", providers: [.apt(["libgd-dev"]), .brew(["gd"])]),
        .systemLibrary(name: "jpeg", pkgConfig: "libjpeg", providers: [.apt(["libjpeg-dev"]), .brew(["jpeg"])]),
        .target(name: "gdOverrides", dependencies: ["gd", "jpeg"]),
		.target(name: "App", dependencies: ["gd",
											"jpeg",
											"gdOverrides",
											.product(name: "Fluent", package: "fluent"),
											.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
											.product(name: "Vapor", package: "vapor"),
											.product(name: "Redis", package: "redis"),
											.product(name: "Leaf", package: "leaf"),
											.product(name: "SwiftPrometheus", package: "SwiftPrometheus"),
								],
								resources: [.copy("Resources"),
											.copy("seeds")
								]),
		.executableTarget(name: "Run", dependencies: ["App"], resources [.copy("Private Swiftarr Config")]),
		.testTarget(name: "AppTests", dependencies: ["App"])
	],
	cLanguageStandard: .c11
)
