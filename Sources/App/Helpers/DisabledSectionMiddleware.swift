import Foundation
import Vapor

struct DisabledAPISectionMiddleware: Middleware {
	let featureToCheck: SwiftarrFeature

	init(feature: SwiftarrFeature) {
		featureToCheck = feature
	}

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		let features = Settings.shared.disabledFeatures.value
		if features[.all]?.contains(featureToCheck) ?? false {
			return request.eventLoop.future(error: Abort(.serviceUnavailable))
		}
		return next.respond(to: request)
	}
}

struct DisabledSiteSectionMiddleware: Middleware {
	let featureToCheck: SwiftarrFeature

	init(feature: SwiftarrFeature) {
		featureToCheck = feature
	}

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		let features = Settings.shared.disabledFeatures.value
		if features[.all]?.contains(featureToCheck) ?? false || features[.swiftarr]?.contains(featureToCheck) ?? false {
			struct DisabledSectionContext : Encodable {
				var trunk: TrunkContext
				init(_ req: Request) {
					trunk = .init(req, title: "Disabled Section", tab: .none)
				}
			}
			let ctx = DisabledSectionContext(request)
			return request.view.render("featureDisabled.leaf", ctx).encodeResponse(for: request)
		}
		return next.respond(to: request)
	}
}
