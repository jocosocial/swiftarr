

/// The type of model for which an `ImageHandler` is processing. This defines the
/// size of the thumbnail produced.

enum ImageHandlerType: String {
    /// The image is for a `ForumPost`.
    case forumPost
    /// The image is for a `Twarrt`
    case twarrt
    /// The image is for a `User`'s profile.
    case userProfile
}
