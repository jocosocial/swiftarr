// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "swiftarr",
	platforms: [
		.macOS(.v13)
	],
	dependencies: [
		// Vapor is the server package underlying Twitarr
		.package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
		// Fluent is an SQL db access package and ORM layer that works with several SQL dbs; we use Postgres underneath it.
		.package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        // Redis is a key-value style non-SQL db we use for various kinds of caches
		.package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
		// Vapor Queues is like Ruby's Sidekiq, or ... cron. We use it to manage time-triggered jobs.
		.package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.1.1"),
		// Leaf is an HTML templating engine, used to build the HTML front end.
		.package(url: "https://github.com/vapor/leaf.git", from: "4.3.0"),
		// Prometheus is a monitoring package
		.package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
		// Ink is a Markdown parser that can output HTML
		.package(url: "https://github.com/johnsundell/ink.git", from: "0.6.0"),
		// Zip compress/decompress
		.package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
		// Excel file parser. I forked this repo from /CoreOffice to fix a few bugs.
		.package(url: "https://github.com/challfry/CoreXLSX.git", .upToNextMinor(from: "0.14.1")),
		// SwiftSoup is a HTML parser we use to scrape webpages.
	    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
	    // Cross-platform QR Code generator. Linux doesn't have access to Core Image
		.package(url: "https://github.com/ApolloZhu/swift_qrcodejs.git", from: "2.2.2"),
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
				.product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
				.product(name: "Prometheus", package: "swift-prometheus"),
				.product(name: "Ink", package: "ink"),
				.product(name: "CoreXLSX", package: "CoreXLSX"),
				.product(name: "SwiftSoup", package: "SwiftSoup"),
				"gd",
				"jpeg",
				"gdOverrides",
				"ZIPFoundation",
				.product(name: "QRCodeSwift", package: "swift_qrcodejs"),
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
//	.enableUpcomingFeature("StrictConcurrency"),
] }

/// Because I have discovered and forgotten this 3 times now, and because it's difficult to find the answer as it's Google-obscured:
///
/// To make changes to a package and test them in Swiftarr, checkout the package locally and replace the `.package(url:...)` line with `.package(path: "<filepath>")`.
/// Accessing the package this way also makes it not process any version restrictions.
/// The path is rooted at the Package.swift's directory, may include `../..` and can probably include absolute paths.
/// 
/// I'm calling this solution 'google-obscured' because there's tons of info out there on how to edit a package that's part of a `.xcodeproj` project file, and the method to do that
/// is very different than how to do it with a `Package.swift` project.
