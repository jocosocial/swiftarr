Canonical Links
===============

Canonical links are links that should always work, even if we rip out the V3 frontend and replace it with something else. This allows client developers to confidently open web views inside their app, or intercept web links and show an app view instead.

All the canonical routes are GET method routes that return HTML pages. Clients should not, for example, open a web view and directly POST to /logout. Use /api/v3/logout instead.

Also, the current frontend is not designed to operate in a boxed context, where the nav bar is removed and the user is 'boxed' into either a single page or a set sequence of pages, and can't just navigate through the entire site. Be sure to explain to the user that they should come back to the app when they're done, otherwise they may stay inside the web view and think the web view *is* the app.

Finally, the frontend currently doesn't provide an easy way to signal that an operation is completed and the app can close the web view.

## Open Access Routes

These routes do not require any authorization header to access. 

Method | Route | Notes
--- | --- | ---
| GET | /login | You probably don't want to open a web view for users to log in, as you won't get the token (the web pages use session auth) and you can't use session auth for API calls. Intercepting the login URL and fulfilling the request in-app makes sense, however.
| GET | /createAccount | If you don't want to build native UI for this, you could open a web view, let the user make their account, and then show them a native login screen.
| GET | /resetPassword | Another seldom-used but important page that could work well as a in-app web view.
| GET | /codeOfConduct | An easy way to put this info in your app if you don't want a custom view.

## Token Access Routes

These routes may be used with Bearer Authentication, where you provide a Token to auth to the server. See `/api/v3/login`. However, these routes will respond with a session cookie, and (most browser clients) use the cookie to perform Session auth for future requests.

Routes not listed on this table MAY NOT work with token auth! If you have a token, you cannot use the token to (for example) auth a POST to a page on the website as if a form had been filled out. You should instead find the API call that does the same function and use that.

Method | Route | Notes
--- | --- | ---
| GET | /logout | This GETs a page that has a logout button. Probably not a great user experience to open a web view just so the user can click the button and logout.
| GET | /createAltAccount | Lets the current user create an alternate account. 
| GET | /tweets | Shows tweets from the tweet stream. Supports a bunch of query options.
| GET | /tweets/:twarrt_id | Shows a thread in the tweet stream. Supports a bunch of query options.
| GET | /forums | Shows forum categories.
| GET | /forums/:category_id | Shows forum threads in a category
| GET | /forum/:forum_id | Shows an individual forum thread.
| GET | /forum/containingpost/:post_id | Shows the forum containing a specific post.
| GET | /seamail | Shows the root seamail page, with a list of all the user's seamail chats.
| GET | /chatgroup/ | Root LFG page.
| GET | /chatgroup/joined | Shows LFGs you've joined.
| GET | /chatgroup/owned | Shows LFGs you've created.
| GET | /chatgroup/:chatgroup_id | Shows a specific LFG.
| GET | /chatgroup/faq | Shows a guide to using LFGs responsibly.
| GET | /events | Shows the Events page. Several query options.
| GET | /avatar/full/:user_id | Returns an image (not HTML wrapping an image)
| GET | /avatar/thumb/:user_id | Returns an image
| GET | /user/:user_id | Shows the user profile page for the indicated user.
| GET | /profile/:username | Shows the user profile page for the user with the given username.
| GET | /boardgames | Shows the boardgames list
| GET | /boardgames/:boardgame_id/expansions | Shows expansions for the given board game
| GET | /karaoke/ | Show the root Karaoke page, with recently sung songs and the library search bar.
