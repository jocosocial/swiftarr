import Foundation
import Vapor
import FluentSQL

extension Route {
	/// Adds metadata to a route that describes in user-visible terms where the route takes the user.
	/// String takes the form of completing "Logging in will let you see ..."
	@discardableResult
    public func destination(_ string: String) -> Route {
        self.userInfo["destination"] = string
        return self
    }
    
	/// Adds metadata to a route that marks it as being used during the preregistration flow. Instead of special-casing the 
	/// middleware these methods use, it's easier to decorate their routes.
	@discardableResult
    public func setUsedForPreregistration() -> Route {
        self.userInfo["usedForPreregistration"] = true
        return self
    }
    
    public func usedForPreregistration() -> Bool {
		return (self.userInfo["usedForPreregistration"] as? Bool?) == true
    }

	/// Adds metadata to a site route that indicates whether it should reutrn JSON or HTML errors. Overrides logic
	/// in SiteErrorMiddleware.
	@discardableResult public func setErrorSchemeOverride(htmlErrors: Bool) -> Route {
        self.userInfo["htmlErrors"] = htmlErrors
        return self
    }
    
    public func errorSchemeOverride() -> Bool? {
		return self.userInfo["htmlErrors"] as? Bool ?? nil
    }
}


extension Request {
	/// Returns a database sort direction for queries based on the Request's `order` parameter. If the `order` is not passed
	/// or invalid, we return nil so the caller can fall back to a default.
	public func orderDirection() -> DatabaseQuery.Sort.Direction? {
		switch query[String.self, at: "order"] {
		case "ascending":
			return DatabaseQuery.Sort.Direction.ascending
		case "descending":
			return DatabaseQuery.Sort.Direction.descending
		default:
			return nil
		}
	}
}
