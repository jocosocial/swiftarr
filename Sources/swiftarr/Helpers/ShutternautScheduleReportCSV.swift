import Foundation

/// Builds a UTF-8 CSV (with BOM) from Shutternaut photography-coverage rows.
/// Used by `GET /api/v3/events/photographerreport/download` and available to any client
/// that already has `[ShutternautScheduleReportData]`.
final class ShutternautScheduleReportCSV {
	static func build(from events: [ShutternautScheduleReportData]) -> Data {
		func csvRecord(fields: String...) -> String {
			return fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
				.joined(separator: ",")
				.appending("\n")
		}
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "MMM d, h:mm a"
		var csv = "\u{FEFF}" + csvRecord(
			fields: "Start Time",
			"End Time",
			"Time Zone",
			"Title",
			"Location",
			"Photographers",
			"Needs Photographed"
		)
		for event in events {
			dateFormatter.timeZone = Settings.shared.timeZoneChanges.tzAtTime(event.startTime)
			csv.append(
				csvRecord(
					fields: dateFormatter.string(from: event.startTime),
					dateFormatter.string(from: event.endTime),
					event.timeZone,
					event.title,
					event.location,
					event.photographers.map { $0.username }.joined(separator: "; "),
					event.needsPhotographer ? "true" : "false"
				)
			)
		}
		return Data(csv.utf8)
	}
}
