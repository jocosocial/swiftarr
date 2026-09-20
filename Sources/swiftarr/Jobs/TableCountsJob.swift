import Fluent
import Metrics
import Queues
import Vapor

/// Job that periodically recomputes the table-count rollup (same data as `GET /api/v3/admin/rollup`)
/// and stores it as Prometheus gauges. Runs on its own timer, independent of how often Prometheus
/// scrapes `/api/v3/client/metrics`, so a scrape never triggers a fresh round of COUNT queries.
///
/// Also invoked once at startup (see `postBootConfigure`) so the gauges aren't simply absent from
/// `/api/v3/client/metrics` for up to a full schedule interval after every restart.
struct TableCountsJob: AsyncScheduledJob {
	func run(context: QueueContext) async throws {
		try await Self.recordTableCounts(on: context.application.db, logger: context.logger)
	}

	static func recordTableCounts(on db: Database, logger: Logger) async throws {
		logger.debug("Starting TableCountsJob")
		let rollup = try await ServerRollupData.computeRollupCounts(on: db)
		for countType in ServerRollupData.CountType.allCases {
			let gauge = Gauge(label: "swiftarr_table_row_count", dimensions: [("table", countType.metricName)])
			gauge.record(Int64(rollup.counts[countType.rawValue]))
		}
		logger.debug("Finished TableCountsJob")
	}
}
