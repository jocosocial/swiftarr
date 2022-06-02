**STRUCT**

# `BoardgameData`

```swift
public struct BoardgameData: Content
```

Used to obtain a list of board games. 

Each year there's a list of boardgames published that'll be brought onboard for the games library. The board game data is produced
by running a script that pulls game data from `http://boardgamegeek.com`'s API and merging it with the games library table.

Games in the library may not match anything in BGG's database (or we can't find a match), so all the BGG fields are optional.

Returned by:
* `GET /api/v3/boardgames` (inside `BoardgameResponseData`)
* `GET /api/v3/boardgames/:boardgameID`
* `GET /api/v3/boardgames/expansions/:boardgameID`

See `BoardgameController.getBoardgames(_:)`, `BoardgameController.getExpansions(_:)`.
