import RediStack

// Different settings for event and LFG notifications. Since this is used as a StoredSettingValue
// this enum has to be Redis-able.
public enum EventNotificationSetting: String, Codable, RESPValueConvertible {
    public init?(fromRESP value: RediStack.RESPValue) {
        guard let stringValue = value.string else {
            return nil
        }
        self.init(rawValue: stringValue)
    }

    public func convertedToRESPValue() -> RediStack.RESPValue {
        return .init(from: rawValue)
    }

	/// Notifications should be disabled.
	case disabled = "disabled"
	/// Pretend that we are at this time but during the cruise week.
	case cruiseWeek = "cruiseWeek"
	/// The current actual real time and date.
	case current = "current"
}
