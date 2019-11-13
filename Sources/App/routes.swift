import Vapor

/// Register your application's routes here.
public func routes(_ router: Router) throws {
    // Basic "It works" example
    router.get { req in
        return "It works!"
    }
    
    let adminController = AdminController()
    try router.register(collection: adminController)
    
    let authController = AuthController()
    try router.register(collection: authController)
    
    let testController = TestController()
    try router.register(collection: testController)
    
    let userController = UserController()
    try router.register(collection: userController)
}
