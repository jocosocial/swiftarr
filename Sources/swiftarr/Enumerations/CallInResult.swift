/// The result of calling in a possible answer for a puzzle.

public enum CallInResult: String, Codable, Sendable {
  /// The call-in was not recognized
  case incorrect

  /// The call-in was not the answer, but was recognized and yielded a clue phrase.
  case hint

  /// The call-in was the correct answer, and the puzzle is now solved.
  case correct
}
