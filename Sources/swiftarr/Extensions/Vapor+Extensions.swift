import Foundation
import Vapor

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

}
