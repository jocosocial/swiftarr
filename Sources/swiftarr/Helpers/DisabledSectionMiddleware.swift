import Foundation
import Vapor

struct DisabledAPISectionMiddleware: AsyncMiddleware {
	let featureToCheck: SwiftarrFeature

	init(feature: SwiftarrFeature) {
		featureToCheck = feature
	}

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		if Settings.shared.disabledFeatures.isFeatureDisabled(featureToCheck) {
			// Allow THO and Admin accounts to continue to use Twitarr features even if sections are disabled.
			if let cacheUser = request.auth.get(UserCacheData.self), (["THO", "admin"].contains(cacheUser.username)) {
				return try await next.respond(to: request)
			}
			throw Abort(.unavailableForLegalReasons, reason: "This feature has been disabled by the server admins.")
		}
		return try await next.respond(to: request)
	}
}

struct DisabledSiteSectionMiddleware: AsyncMiddleware {
	let featureToCheck: SwiftarrFeature

	init(feature: SwiftarrFeature) {
		featureToCheck = feature
	}

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		if Settings.shared.disabledFeatures.isFeatureDisabled(featureToCheck, inApp: .swiftarr) {
			// Allow THO and Admin accounts to continue to use Twitarr features even if sections are disabled.
			if let cacheUser = request.auth.get(UserCacheData.self), (["THO", "admin"].contains(cacheUser.username)) {
				await request.storage.setWithAsyncShutdown(FeatureDisableOverrideStorageKey.self, to: featureToCheck)
				return try await next.respond(to: request)
			}
			struct DisabledSectionContext: Encodable {
				var trunk: TrunkContext
				init(_ req: Request) {
					trunk = .init(req, title: "Disabled Section", tab: .none)
				}
			}
			let ctx = DisabledSectionContext(request)
			return try await request.view.render("featureDisabled.html", ctx).encodeResponse(for: request)
		}
		return try await next.respond(to: request)
	}
}

// DisabledSiteSectionMiddleware stores this in Request.storage when THO or admin access a page that's disabled for everyone else.
// The Trunk leaf template then displays an alert telling the user that the page is, in fact, disabled for normal users.
struct FeatureDisableOverrideStorageKey: StorageKey {
	typealias Value = SwiftarrFeature
}
