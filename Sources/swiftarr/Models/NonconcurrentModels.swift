import Foundation

// This file contains extensions to disable Sendable checking for model classes
// that are not expected to be used across actor boundaries

extension OAuthClient: @unchecked Sendable {}
extension OAuthCode: @unchecked Sendable {}
extension OAuthToken: @unchecked Sendable {}