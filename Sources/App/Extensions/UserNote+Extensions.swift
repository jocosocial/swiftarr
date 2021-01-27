import Vapor
import Fluent

// MARK: - Methods

extension UserNote {
    /// Converts a `UserNote` model to a version intended for editing by the owning
    /// user. Essentially just the text, and the note's ID so that the edit can be directly
    /// submitted for update.
    func convertToEdit() throws -> NoteEditData {
        return try NoteEditData(
            noteID: self.requireID(),
            note: self.note
        )
    }
}
