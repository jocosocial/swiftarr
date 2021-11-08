import Vapor
import Fluent


/// A `Migration` that imports the event schedule from a `schedule.ics` file
/// located in the `seeds/` subdirectory of the project.
struct ImportEvents: Migration {    
    /// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
    /// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
    /// a parser and populates the `Event` database with the `[Event]` array returned.
    ///
    /// - Requires: `schedule.ics` file in seeds subdirectory.
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        // get schedule.ics
        let scheduleFile: String
        do {
            if (try Environment.detect().isRelease) {
                scheduleFile = "schedule.ics"
            } else {
                scheduleFile = "test-schedule.ics"
            }
            let directoryConfig = DirectoryConfiguration.detect()
            let schedulePath = directoryConfig.workingDirectory.appending("seeds/").appending(scheduleFile)
            // read file as string
            guard let data = FileManager.default.contents(atPath: schedulePath),
                let dataString = String(bytes: data, encoding: .utf8) else {
                    fatalError("Could not read schedule file.")
            }
            // parse to events
            let scheduleEvents = EventParser().parse(dataString)
            let eventFutures = scheduleEvents.map { event in event.save(on: database) }
 			return eventFutures.flatten(on: database.eventLoop).transform(to: ())
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
		return database.schema("events").delete()
    }
}
