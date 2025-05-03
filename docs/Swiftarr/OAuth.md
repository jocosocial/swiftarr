# OIDC
SwiftArr supports third-party applications using SwiftArr as their Identity Provider (IdP) using the OpenID Connect 2.0 framework. This allows third-party apps to leverage the legwork that the TwitArr dev team does every year to create accounts for each cruise attendee, moderate those accounts, etc.

## Example Ideas:
* A ship-wide chess match where each user can take a turn once per day, Red Team vs Gold Team
* A photo sharing service (TODO: Link it here)

## Important Information
1. All apps developed must adhere to the Joco Cruise Code of Conduct
2. Aboard the ship, devices are firewalled from each other and unable to communicate across the network. Therefore, all apps must be hosted on the TwitArr team's server in the ship's data center
3. Come talk to us in #twitarr on [the Joco Cruise official discord](https://discord.com/invite/dVT3E3raAc) if you are interested in developing an app that connects with TwitArr. Feel free to ping Bruce (@agentk) with any specific questions.

## Using the OAuth/OIDC Endpoints
To use the OIDC authentication flow:

1. **Register your client application** in the SwiftArr admin interface
2. **Request authorization** by redirecting users to `/oidc/authorize` with the required parameters
3. **Handle the authorization code** callback and exchange it for access tokens

### Authorization Request
Redirect users to `/oidc/authorize` with the following parameters:
- `client_id`: Your registered client ID
- `redirect_uri`: The URI to redirect to after authorization (must be registered with your client)
- `response_type`: Use `code` for the authorization code flow
- `scope`: Space-separated list of requested scopes (must include `openid`)
- `state` (recommended): A random string to prevent CSRF attacks


## Available Scopes offered by TwitArr
- `openid` - The default claim, required for all OIDC requests. Allows the application to authenticate you as a TwitArr user.
- `twitarr:photostream:view` - Allows the application to view photos you've submitted to the photostream.
- `twitarr:photostream:submit` - Allows the application to submit photos to the photostream on your behalf.
- `twitarr:user:username` - Allows the application to see your username.
- `twitarr:user:publicinfo` - Allows the application to see your public profile information including your name, pronouns, and dinner team.
- `twitarr:user:message` - Allows the application to send direct messages and seamail to you.
- `twitarr:user:notify` - Allows the application to send you push notifications.
- `twitarr:user:view-avatar` - Allows the application to view your profile picture.
- `twitarr:user:view-access-level` - Allows the application to see your access level on TwitArr (user, moderator, admin, etc.).

Each scope represents a specific permission that your application can request. Users will be shown these permissions during the consent process and can choose to grant or deny access.
