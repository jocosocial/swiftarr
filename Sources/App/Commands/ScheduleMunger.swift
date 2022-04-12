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
		@Argument(name: "inputFilePath")
		var inputFilePath: String

		@Argument(name: "outputFilePath")
		var outputFilePath: String
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

		let outputFile = URL(fileURLWithPath: signature.outputFilePath)

		guard let data = FileManager.default.contents(atPath: signature.inputFilePath),
			let fileString = String(bytes: data, encoding: .utf8)
		else {
			fatalError("Could not read schedule file.")
		}

		let astStartDate = Settings.shared.getDisplayCalendar().date(
			from: DateComponents(
				calendar: Settings.shared.getDisplayCalendar(),
				timeZone: Settings.shared.portTimeZone, year: 2022, month: 3, day: 8, hour: 2))!
		let astEndDate = Settings.shared.getDisplayCalendar().date(
			from: DateComponents(
				calendar: Settings.shared.getDisplayCalendar(),
				timeZone: Settings.shared.portTimeZone, year: 2022, month: 3, day: 9, hour: 2))!

		if FileManager.default.fileExists(atPath: outputFile.path) {
			try FileManager.default.removeItem(at: outputFile)
		}

		let icsArray = fileString.components(separatedBy: .newlines)
		for element in icsArray where !element.isEmpty {
			let pair = element.split(separator: ":", maxSplits: 1)
			let key = String(pair.first ?? "")
			let value = String(pair.last ?? "")
			switch key {
			case "DTSTART", "DTEND":
				if var date = dateFormatter.date(from: value), astStartDate < date, date <= astEndDate {
					date -= 3600
					writeOutputLine("\(key):\(dateFormatter.string(from: date))", fileUrl: outputFile)
				} else {
					writeOutputLine("\(element)", fileUrl: outputFile)
				}
			default:
				writeOutputLine("\(element)", fileUrl: outputFile)
			}
		}
	}

	// StackOverflow the real MVP of all this.
	// https://stackoverflow.com/questions/54384781/how-to-create-a-file-in-the-documents-folder-if-one-doesnt-exist
	func writeOutputLine(_ line: String, fileUrl: URL) {
		let formatedLine = "\(line)\r\n"
		if let handle = try? FileHandle(forWritingTo: fileUrl) {
			handle.seekToEndOfFile()
			handle.write(formatedLine.data(using: .utf8)!)
			handle.closeFile()
		} else {
			do {
				try formatedLine.write(to: fileUrl, atomically: false, encoding: .utf8)
			} catch {
				fatalError("Unable to write to new file: \(error)")
			}
		}
	}
}