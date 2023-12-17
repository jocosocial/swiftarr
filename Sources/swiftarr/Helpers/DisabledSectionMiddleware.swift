import Foundation
import Vapor

struct DisabledAPISectionMiddleware: AsyncMiddleware {
	let featureToCheck: SwiftarrFeature

	init(feature: SwiftarrFeature) {
		featureToCheck = feature
	}

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		let features = Settings.shared.disabledFeatures.value
		if features[.all]?.contains(featureToCheck) ?? false || features[.all]?.contains(.all) ?? false {
			// There are a couple StackOverflow posts discussing what code is most appropriate
			// for a "correct request but the server refuses to process it" situation like this.
			// The 451 Legal Reasons code is so far out out there that I think we're in safe
			// position to use that as the code for "we've disabled this feature".
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
		let features = Settings.shared.disabledFeatures.value
		if features[.all]?.contains(.all) ?? false || features[.all]?.contains(featureToCheck) ?? false
			|| features[.swiftarr]?.contains(.all) ?? false || features[.swiftarr]?.contains(featureToCheck) ?? false
		{
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
