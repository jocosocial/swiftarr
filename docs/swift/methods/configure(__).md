### `configure(_:)`

```swift
public func configure(_ app: Application) throws
```

# Launching Swiftarr

### Environment

Besides the standard .development, .production, and .testing, there's a few custom environment values that can be set, either on the command line
with `--env <ENVIRONMENT>` or with the `VAPOR_ENV` environment variable
* --env heroku: Use this for Heroku installs. This changes the Migrations for games and karaoke to load fewer items and use fewer table rows. It also
	may change the way images are stored. Otherwise like .production.

Environment variables used by Swiftarr:
* DATABASE_URL: 
* DATABASE_HOSTNAME:
* DATABASE_PORT:
* DATABASE_DB:
* DATABASE_USER:
* DATABASE_PASSWORD:

* REDIS_URL:
* REDIS_HOSTNAME: 

* PORT:
* hostname:

* ADMIN_PASSWORD:
* RECOVERY_KEY:

* SWIFTARR_USER_IMAGES:  Root directory for storing user-uploaded images. These images are referenced by filename in the db.

Called before your application initializes. Calls several other config methods to do its work. Sub functions are only
here for easier organization. If order-of-initialization issues arise, rearrange as necessary.
