// swift-tools-version:6.0
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
		.package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
		.package(url: "https://github.com/challfry/CoreXLSX.git", .upToNextMinor(from: "0.14.1")),
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
				.product(name: "CoreXLSX", package: "CoreXLSX"),
				"gd",
				"jpeg",
				"gdOverrides",
				"ZIPFoundation",
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
	swiftLanguageVersions: [.v5],
	cLanguageStandard: .c11
)

var swiftSettings: [SwiftSetting] { [
	// These four will be necessary for Swift 6 compatibility.
	// .enableUpcomingFeature("DisableOutwardActorInference"),
	// .enableUpcomingFeature("GlobalConcurrency"),
	// .enableUpcomingFeature("InferSendableFromCaptures"),
	// .enableUpcomingFeature("StrictConcurrency"),
	//
	// And these are here from past experiments.
	// .enableUpcomingFeature("BareSlashRegexLiterals"),
	// .enableExperimentalFeature("StrictConcurrency"),
	// .unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"])
	// .unsafeFlags(["-Xfrontend", "-warn-concurrency"])
] }

/// Because I have discovered and forgotten this 3 times now, and because it's difficult to find the answer as it's Google-obscured:
///
/// To make changes to a package and test them in Swiftarr, checkout the package locally and replace the `.package(url:...)` line with `.package(path: "<filepath>")`.
/// Accessing the package this way also makes it not process any version restrictions.
/// The path is rooted at the Package.swift's directory, may include `../..` and can probably include absolute paths.
/// 
/// I'm calling this solution 'google-obscured' because there's tons of info out there on how to edit a package that's part of a `.xcodeproj` project file, and the method to do that
/// is very different than how to do it with a `Package.swift` project.
