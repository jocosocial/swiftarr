import Foundation
import Fluent

// This file contains Migrations that create the initial database schema. 
// These migrations do not migrate from an old schema to a new one--they migrate from nothing. 

// This migration creates custom enum types used by the database. Other migrations then use these
// custom types to define enum-valued fields.
struct CreateCustomEnums: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
		let enums = [
			database.enum("moderation_status")
				.case("normal")
				.case("autoQuarantined")
				.case("quarantined")
				.case("modReviewed")
				.case("locked")
				.create(),
			database.enum("user_access_level")
				.case("unverified")
				.case("banned")
				.case("quarantined")
				.case("verified")
				.case("client")
				.case("moderator")
				.case("tho")
				.case("admin")
				.create()
		]
		return enums.flatten(on: database.eventLoop).transform(to: database.eventLoop.future())			
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.enum("moderation_status").delete()
    }
}

struct CreateAnnouncementSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("announcements")
				.field("id", .int, .identifier(auto: true))
				.field("text", .string, .required)
				.field("display_until", .datetime, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
    			.field("deleted_at", .datetime)
				.field("author", .uuid, .required, .references("users", "id"))
				.create()
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("announcements").delete()
    }
}

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
		database.enum("user_access_level").read().flatMap { userAccessLevel in
			database.schema("categories")
					.id()
					.field("title", .string, .required)
					.unique(on: "title")
					.field("view_access_level", userAccessLevel, .required)
					.field("create_access_level", userAccessLevel, .required)
					.field("forumCount", .int32, .required)
					.field("created_at", .datetime)
					.field("updated_at", .datetime)
					.field("deleted_at", .datetime)
					.create()
		}
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("categories").delete()
    }
}

struct CreateDailyThemeSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("daily_theme")
				.id()
				.field("title", .string, .required)
				.field("info", .string, .required)
				.field("image", .string)
				.field("cruise_day", .int32, .required)
				.unique(on: "cruise_day")
				.create()
	}
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("daily_theme").delete()
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
    			.field("forum_id", .uuid, .references("forums", "id", onDelete: .setNull))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("events").delete()
    }
}

struct CreateFezPostSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.enum("moderation_status").read().flatMap { modStatusEnum in
			database.schema("fezposts")
					.field("id", .int, .identifier(auto: true))
					.field("text", .string, .required)
					.field("image", .string)
					.field("mod_status", modStatusEnum, .required)
					.field("created_at", .datetime)
					.field("updated_at", .datetime)
					.field("deleted_at", .datetime)
					.field("friendly_fez", .uuid, .required, .references("friendlyfez", "id"))
					.field("author", .uuid, .required, .references("users", "id"))
					.create()
		}
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("fezposts").delete()
    }
}

struct CreateForumSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.enum("moderation_status").read().flatMap { modStatusEnum in
			database.schema("forums")
					.id()
					.field("title", .string, .required)
					.field("mod_status", modStatusEnum, .required)
					.field("created_at", .datetime)
					.field("updated_at", .datetime)
					.field("deleted_at", .datetime)
					.field("category_id", .uuid, .required, .references("categories", "id"))
					.field("creator_id", .uuid, .required, .references("users", "id"))
					.create()
		}
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forums").delete()
    }
}

struct CreateForumEditSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forum_edits")
				.id()
				.field("title", .string, .required)
    			.field("created_at", .datetime)
 				.field("forum", .uuid, .required, .references("forums", "id"))
 				.field("editor", .uuid, .required, .references("users", "id"))
				.create()
	}
	
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forum_edits").delete()
    }
}

struct CreateForumPostEditSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forum_post_edits")
				.id()
				.field("post_text", .string, .required)
				.field("images", .array(of: .string))
    			.field("created_at", .datetime)
 				.field("post", .int, .required, .references("forumposts", "id"))
 				.field("editor", .uuid, .required, .references("users", "id"))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forum_post_edits").delete()
    }
}

struct CreateForumReadersSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forum+readers")
				.id()
				.unique(on: "user", "forum")
				.field("read_count", .int, .required)
 				.field("user", .uuid, .required, .references("users", "id", onDelete: .cascade))
  				.field("forum", .uuid, .required, .references("forums", "id", onDelete: .cascade))
				.create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forum+readers").delete()
    }
}

struct CreateForumPostSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.enum("moderation_status").read().flatMap { modStatusEnum in
			database.schema("forumposts")
					.field("id", .int, .identifier(auto: true))
					.field("text", .string, .required)
					.field("images", .array(of: .string))
					.field("mod_status", modStatusEnum, .required)
					.field("created_at", .datetime)
					.field("updated_at", .datetime)
					.field("deleted_at", .datetime)
					.field("forum", .uuid, .required, .references("forums", "id"))
					.field("author", .uuid, .required, .references("users", "id"))
					.create()
		}
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forumposts").delete()
    }
}

struct CreateFriendlyFezSchema: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.enum("moderation_status").read().flatMap { modStatusEnum in
			database.schema("friendlyfez")
					.id()
					.field("fezType", .string, .required)
					.field("title", .string, .required)
					.field("info", .string, .required)
					.field("location", .string)
					.field("mod_status", modStatusEnum, .required)
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
	}
 
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("friendlyfez").delete()
    }
}

struct CreateFriendlyFezEditSchema: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("fez_edits")
				.id()
				.field("title", .string, .required)
				.field("info", .string, .required)
				.field("location", .string, .required)
    			.field("created_at", .datetime)
 				.field("fez", .uuid, .required, .references("friendlyfez", "id"))
 				.field("editor", .uuid, .required, .references("users", "id"))
				.create()
	}
	
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("fez_edits").delete()
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

struct CreateModeratorActionSchema: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema("moderator_actions")
				.id()
				.field("action_type", .string, .required)
				.field("content_type", .string, .required)
				.field("content_id", .string, .required)
				.field("action_group", .uuid)
    			.field("created_at", .datetime)
 				.field("actor", .uuid, .required, .references("users", "id"))
 				.field("target_user", .uuid, .required, .references("users", "id"))
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
 				.field("editor", .uuid, .required, .references("users", "id"))
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
				.field("action_group", .uuid)
				.field("isClosed", .bool, .required)
    			.field("created_at", .datetime)
    			.field("updated_at", .datetime)
 				.field("author", .uuid, .required, .references("users", "id"))
 				.field("reportedUser", .uuid, .required, .references("users", "id"))
 				.field("handled_by", .uuid, .references("users", "id"))
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
		database.enum("moderation_status").read().flatMap { modStatusEnum in
			database.schema("twarrts")
					.field("id", .int, .identifier(auto: true))
					.field("text", .string, .required)
					.field("images", .array(of: .string))
					.field("mod_status", modStatusEnum, .required)
					.field("created_at", .datetime)
					.field("updated_at", .datetime)
					.field("deleted_at", .datetime)
					.field("author", .uuid, .required, .references("users", "id"))
					.field("reply_group", .int, .references("twarrts", "id"))
					.create()
		}
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
				.field("images", .array(of: .string))
    			.field("created_at", .datetime)
 				.field("twarrt", .int, .references("twarrts", "id"))
 				.field("editor", .uuid, .references("users", "id"))
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
		database.enum("moderation_status").read().flatMap { modStatusEnum in
		database.enum("user_access_level").read().flatMap { userAccessLevel in
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
					.field("accessLevel", userAccessLevel, .required)
					.field("moderationStatus", modStatusEnum, .required)
					.field("recoveryAttempts", .int, .required)
					.field("reports", .int, .required)
					.field("tempQuarantineUntil", .datetime)
					
					.field("userImage", .string)
					.field("about", .string)
					.field("email", .string)
					.field("homeLocation", .string)
					.field("message", .string)
					.field("preferredPronoun", .string)
					.field("roomNumber", .string)
					
					.field("last_read_announcement", .int)
					.field("twarrt_mentions", .int)
					.field("twarrt_mentions_viewed", .int)
					.field("forum_mentions", .int)
					.field("forum_mentions_viewed", .int)
					
					.field("action_group", .uuid)

					.field("created_at", .datetime)
					.field("updated_at", .datetime)
					.field("deleted_at", .datetime)
					.field("profileUpdatedAt", .datetime, .required)
					.field("parent", .uuid, .references("users", "id"))
					.create()
		}
		}
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
