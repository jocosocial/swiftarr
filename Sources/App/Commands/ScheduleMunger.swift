import Vapor

/// Parser for a sched.com `.ics` file, based on https://jococruise2019.sched.com export.
/// This parser is specifically written to correct times when the boat will be in the AST timezone, but the Sched.com export has times
/// that are correct in the EST timezone, because Sched doesn't support having a venue move between timezones during an event.
///
/// To use:
//		./munger schedule.ics > munged.ics
///
///	Then take the munged.ics file and either replace /Sources/App/seeds/schedule.ics with it, or use the Admin UI to apply munged.ics as a schedule update.
struct ScheduleMungerCommand: Command {
	struct Signature: CommandSignature {
		@Argument(name: "path")
		var path: String
	}

	var help: String {
		"Pass in a path to a schedule.ics file as first argument"
	}

	func run(using context: CommandContext, signature: Signature) throws {
		/// A `DateFormatter` for converting sched.com's non-standard date strings to a `Date`.
		let dateFormatter: DateFormatter = {
			let dateFormatter = DateFormatter()
			dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
			dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
			return dateFormatter
		}()

		guard let data = FileManager.default.contents(atPath: signature.path),
			let fileString = String(bytes: data, encoding: .utf8)
		else {
			fatalError("Could not read schedule file.")
		}

		let astStartDate = Calendar.current.date(
			from: DateComponents(
				calendar: Calendar.current,
				timeZone: TimeZone(abbreviation: "EST")!, year: 2022, month: 3, day: 8, hour: 2))!
		let astEndDate = Calendar.current.date(
			from: DateComponents(
				calendar: Calendar.current,
				timeZone: TimeZone(abbreviation: "EST")!, year: 2022, month: 3, day: 9, hour: 2))!

		let icsArray = fileString.components(separatedBy: .newlines)
		for element in icsArray where !element.isEmpty {
			let pair = element.split(separator: ":", maxSplits: 1)
			let key = String(pair.first ?? "")
			let value = String(pair.last ?? "")
			switch key {
			case "DTSTART", "DTEND":
				if var date = dateFormatter.date(from: value), astStartDate < date, date <= astEndDate {
					date -= 3600
					print("\(key):\(dateFormatter.string(from: date))", terminator: "\r\n")
				} else {
					print(element, terminator: "\r\n")
				}
			default:
				print(element, terminator: "\r\n")
			}
		}
	}
}