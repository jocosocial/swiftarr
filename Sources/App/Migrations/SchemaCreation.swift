import Foundation
import Fluent

// This file contains Migrations that create the initial database schema. 
// These migrations do not migrate from an old schema to a new one--they migrate from nothing. 

struct CreateBarrelSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("barrels")
				.id()
				.field("ownerID", .uuid, .required)
				.field("barrelType", .string, .required)
				.field("name", .string, .required)
				.field("modelUUIDs", .array(of: .uuid), .required)
				.field("userInfo", .dictionary(of: .array), .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
				.create()
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("barrels").delete()
    }
}

struct CreateCategorySchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("categories")
				.id()
				.field("title", .string, .required)
				.unique(on: "title")
				.field("isRestricted", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
				.create()
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("categories").delete()
    }
}

struct CreateEventSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("events")
				.id()
				.field("uid", .string, .required)
				.unique(on: "uid")
				.field("startTime", .datetime, .required)
				.field("endTime", .datetime, .required)
				.field("title", .string, .required)
				.field("info", .string, .required)
				.field("location", .string, .required)
				.field("eventType", .string, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
    			.field("forum_id", .uuid, .references("forums", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("events").delete()
    }
}

struct CreateFezPostSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("fezposts")
				.id()
				.field("text", .string, .required)
				.field("image", .string, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
 				.field("friendly_fez", .uuid, .required, .references("barrels", "id"))
				.create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("fezposts").delete()
    }
}

struct CreateForumSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forums")
				.id()
				.field("title", .string, .required)
				.field("isLocked", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
 				.field("category_id", .uuid, .required, .references("categories", "id"))
 				.field("creator_id", .uuid, .required, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forums").delete()
    }
}

struct CreateForumEditSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumedits")
				.id()
				.field("postContent", .dictionary, .required)
    			.field("created_at", .datetime)
 				.field("post_id", .uuid, .required, .references("forumposts", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumedits").delete()
    }
}

struct CreateForumPostSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumposts")
				.id()
				.field("text", .string, .required)
				.field("image", .string, .required)
				.field("isQuarantined", .bool, .required)
				.field("isReviewed", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
 				.field("forum", .uuid, .required, .references("forums", "id"))
 				.field("author", .uuid, .required, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumposts").delete()
    }
}

struct CreatePostLikesSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("post+likes")
				.id()
				.field("liketype", .string)
 				.field("user", .uuid, .required, .references("users", "id", onDelete: .cascade))
 				.field("forumPost", .uuid, .required, .references("forumposts", "id", onDelete: .cascade))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("post+likes").delete()
    }
}

struct CreateProfileEditSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("profileedits")
				.id()
				.field("profileData", .dictionary)
				.field("profileImage", .string)
    			.field("created_at", .datetime)
 				.field("userprofile", .uuid, .required, .references("userprofiles", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("profileedits").delete()
    }
}

struct CreateRegistrationCodeSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("registrationcodes")
				.id()
				.field("code", .string, .required)
				.field("profileImage", .string)
    			.field("updated_at", .datetime)
 				.field("user", .uuid, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("registrationcodes").delete()
    }
}

struct CreateReportSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("reports")
				.id()
				.field("reportType", .string, .required)
				.field("reportedID", .string, .required)
				.field("submitterMessage", .string, .required)
				.field("isClosed", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
 				.field("author", .uuid, .required, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("reports").delete()
    }
}

struct CreateTokenSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("tokens")
				.id()
				.field("token", .string, .required)
    			.field("created_at", .datetime)
 				.field("user", .uuid, .required, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("tokens").delete()
    }
}

struct CreateTwarrtSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("twarrts")
				.field("id", .int, .identifier(auto: true))
				.field("text", .string, .required)
				.field("image", .string, .required)
				.field("isQuarantined", .bool, .required)
				.field("isReviewed", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
 				.field("author", .uuid, .required, .references("users", "id"))
 				.field("reply_to", .int, .references("twarrts", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("twarrts").delete()
    }
}

struct CreateTwarrtEditSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("twarrtedits")
				.id()
				.field("twarrtContent", .dictionary, .required)
    			.field("created_at", .datetime)
 				.field("author", .uuid, .required, .references("users", "id"))
 				.field("twarrt", .int, .references("twarrts", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("twarrtedits").delete()
    }
}

struct CreateTwarrtLikesSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("twarrt+likes")
				.id()
				.field("liketype", .string)
 				.field("user", .uuid, .required, .references("users", "id", onDelete: .cascade))
 				.field("twarrt", .int, .required, .references("twarrts", "id", onDelete: .cascade))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("twarrt+likes").delete()
    }
}

struct CreateUserSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
    	database.schema("users")
    			.id()
    			.field("username", .string, .required)
    			.unique(on: "username")
    			.field("password", .string, .required)
    			.field("recoveryKey", .string, .required)
    			.field("verification", .string)
    			.field("accessLevel", .int8, .required)
    			.field("recoveryAttempts", .int, .required)
    			.field("reports", .int, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
    			.field("profileUpdatedAt", .datetime, .required)
    			.field("parent", .uuid, .references("users", "id"))
 //   			.field("user_profile", .uuid, .references("userprofiles", "id"))
    			.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users").delete()
    }
}

struct CreateUserNoteSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("usernotes")
				.id()
				.field("note", .string, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
 				.field("author", .uuid, .required, .references("users", "id"))
 				.field("profile", .uuid, .references("userprofiles", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("usernotes").delete()
    }
}

struct CreateUserProfileSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
    	database.schema("userprofiles")
    			.id()
	   			.field("username", .string, .required)
     			.field("userSearch", .string, .required)
     			.field("userImage", .string, .required)
     			.field("about", .string)
     			.field("displayName", .string)
     			.field("email", .string)
     			.field("homeLocation", .string)
     			.field("message", .string)
     			.field("preferredPronoun", .string)
     			.field("realName", .string)
     			.field("roomNumber", .string)
     			.field("limitAccess", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
     			.field("user", .uuid, .required, .references("users", "id"))
    			.unique(on: "user")
	   			.create()
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("userprofiles").delete()
    }
}

