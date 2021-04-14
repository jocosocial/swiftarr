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
				.field("id", .int, .identifier(auto: true))
				.field("text", .string, .required)
				.field("image", .string)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
 				.field("friendly_fez", .uuid, .required, .references("friendlyfez", "id"))
 				.field("author", .uuid, .required, .references("users", "id"))
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
				.field("post_text", .string, .required)
				.field("image_name", .string)
    			.field("created_at", .datetime)
 				.field("post_id", .int, .required, .references("forumposts", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumedits").delete()
    }
}

struct CreateForumPostSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumposts")
				.field("id", .int, .identifier(auto: true))
				.field("text", .string, .required)
				.field("image", .string)
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

struct CreateFriendlyFezSchema: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema("friendlyfez")
				.id()
				.field("fezType", .string, .required)
				.field("title", .string, .required)
				.field("info", .string, .required)
				.field("location", .string)
				.field("start_time", .datetime)
				.field("end_time", .datetime)
				.field("min_capacity", .int, .required)
				.field("max_capacity", .int, .required)
				.field("post_count", .int, .required)
				.field("cancelled", .bool, .required)
				.field("participant_array", .array(of: .uuid), .required)
				.field("owner", .uuid, .required, .references("users", "id", onDelete: .cascade))
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
				.create()
	}
 
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("friendlyfez").delete()
    }
}

struct CreateFezParticipantSchema: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema("fez+participants")
				.id()
				.unique(on: "user", "friendly_fez")
 				.field("user", .uuid, .required, .references("users", "id", onDelete: .cascade))
 				.field("friendly_fez", .uuid, .required, .references("friendlyfez", "id", onDelete: .cascade))
				.field("read_count", .int, .required)
				.field("hidden_count", .int, .required)
				.create()
	}
 
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("fez+participants").delete()
    }
}

struct CreatePostLikesSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("post+likes")
				.id()
				.unique(on: "user", "forumPost")
				.field("liketype", .string)
 				.field("user", .uuid, .required, .references("users", "id", onDelete: .cascade))
 				.field("forumPost", .int, .required, .references("forumposts", "id", onDelete: .cascade))
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
 				.field("user", .uuid, .required, .references("users", "id"))
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
				.field("image", .string)
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
				.field("text", .string, .required)
				.field("image_name", .string)
    			.field("created_at", .datetime)
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
				.unique(on: "user", "twarrt")
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
     			.field("displayName", .string)
     			.field("realName", .string)
     			.field("userSearch", .string, .required)

    			.field("password", .string, .required)
    			.field("recoveryKey", .string, .required)
    			.field("verification", .string)
    			.field("accessLevel", .int8, .required)
    			.field("recoveryAttempts", .int, .required)
    			.field("reports", .int, .required)
    			
     			.field("userImage", .string)
     			.field("about", .string)
     			.field("email", .string)
     			.field("homeLocation", .string)
     			.field("message", .string)
     			.field("preferredPronoun", .string)
     			.field("roomNumber", .string)
     			.field("limitAccess", .bool, .required)
    			
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
    			.field("profileUpdatedAt", .datetime, .required)
    			.field("parent", .uuid, .references("users", "id"))
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
 				.field("note_subject", .uuid, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("usernotes").delete()
    }
}
