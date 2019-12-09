import Vapor
import FluentPostgreSQL

/// A `Migration` that imports the event schedule from a `schedule.ics` file
/// located in the `seeds/` subdirectory of the project.
struct Events: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
    /// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
    /// a parser and populates the `Event` database with the `[Event]` array returned.
    ///
    /// - Requires: `schedule.ics` file in seeds subdirectory.
    /// - Parameter conn: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on conn: PostgreSQLConnection) -> EventLoopFuture<Void> {
        // get schedule.ics
        let scheduleFile: String
        do {
            if (try Environment.detect().isRelease) {
                scheduleFile = "schedule.ics"
            } else {
                scheduleFile = "test-schedule.ics"
            }
            let directoryConfig = DirectoryConfig.detect()
            let schedulePath = directoryConfig.workDir.appending("seeds/").appending(scheduleFile)
            // read file as string
            guard let data = FileManager.default.contents(atPath: schedulePath),
                let dataString = String(bytes: data, encoding: .utf8) else {
                    fatalError("Could not read schedule file.")
            }
            // transform to array
            let scheduleArray = dataString.components(separatedBy: .newlines)
            // parse to events
            let scheduleEvents = EventParser().parse(scheduleArray, on: conn)
            return scheduleEvents.flatMap {
                (events) in
                events.map { $0.save(on: conn) }.flatten(on: conn).transform(to: ())
            }
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
        }
    }
    
    /// Required by `Migration` protocol, but this is seed data, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter connection: The database connection.
    /// - Returns: Void.
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return .done(on: connection)
    }
}
