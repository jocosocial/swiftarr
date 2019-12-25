import Vapor

/// A (hopefully) thread-safe singleton that provides modifiable global settings.

final class Settings {
    
    /// The shared instance for this singleton.
    static let shared = Settings()
    
    /// DispatchQueue to use for thread-safety synchronization.
    fileprivate let settingsQueue = DispatchQueue(label: "settingsQueue")
    
    /// Required initializer.
    private init() {}
        
    
    /// The ID of the blocked user placeholder.
    var blockedUserID: UUID {
        set(newValue) {
            settingsQueue.async {
                self._blockedUserID = newValue
            }
        }
        get { return settingsQueue.sync { _blockedUserID } }
    }

    /// The ID of the FriendlyFez user placeholder.
    var friendlyFezID: UUID {
        set(newValue) {
            settingsQueue.async {
                self._friendlyFezID = newValue
            }
        }
        get { return settingsQueue.sync { _friendlyFezID } }
    }
    
    // MARK: Limits
    
    /// The maximum number of twartts allowed per request.
    var maximumTwarrts: Int {
        set(newValue) {
            settingsQueue.async {
                self._maximumTwarrts = newValue
            }
        }
        get { return settingsQueue.sync { _maximumTwarrts } }
    }

    // MARK: Quarantine
    
    /// The number of reports to trigger forum auto-quarantine.
    var forumAutoQuarantineThreshold: Int {
        set(newValue) {
            settingsQueue.async {
                self._forumAutoQuarantineThreshold = newValue
            }
        }
        get { return settingsQueue.sync { _forumAutoQuarantineThreshold } }
    }
    
    /// The number of reports to trigger post/twarrt auto-quarantine.
    var postAutoQuarantineThreshold: Int {
        set(newValue) {
            settingsQueue.async {
                self._postAutoQuarantineThreshold = newValue
            }
        }
        get { return settingsQueue.sync { _postAutoQuarantineThreshold } }
    }
    
    /// The number of reports to trigger user auto-quarantine.
    var userAutoQuarantineThreshold: Int {
        set(newValue) {
            settingsQueue.async {
                self._userAutoQuarantineThreshold = newValue
            }
        }
        get { return settingsQueue.sync { _userAutoQuarantineThreshold } }
    }
    
    // MARK: - Internal Storage

    /// Internal storage.
    fileprivate var _blockedUserID: UUID = UUID()
    /// Internal storage.
    fileprivate var _friendlyFezID: UUID = UUID()
    
    /// Internal storage.
    fileprivate var _forumAutoQuarantineThreshold: Int = 3
    /// Internal storage.
    fileprivate var _postAutoQuarantineThreshold: Int = 3
    /// Internal storage.
    fileprivate var _userAutoQuarantineThreshold: Int = 5

    /// Internal storage.
    fileprivate var _maximumTwarrts: Int = 200
    
}
