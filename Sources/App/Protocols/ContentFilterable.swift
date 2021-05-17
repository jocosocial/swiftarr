import Vapor
import Redis

/// A `Protocol` used to provide convenience functions for Models that
/// return content that is filterable on a per-user basis.
protocol ContentFilterable {    
    func containsMutewords(using mutewords: [String]) -> Bool
	func filterMutewords(using mutewords: [String]?) -> Self?
}
