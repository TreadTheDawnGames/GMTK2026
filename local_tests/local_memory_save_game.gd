extends SaveGame

## How it works:
## - Full-scene tests replace GameState's loaded save with this empty resource.
## - Runtime code can still update and inspect every normal SaveGame field.
## - Writes stay in memory so parallel branches cannot race the player's file.
## The invariant is that a local test never mutates user://savegame.tres.


# Keep the no-I/O double signature synchronized with SaveGame so production
# callers can pass an isolated path and still receive the normal Error result.
func write_savegame(_storage_path: String = "") -> Error:
	return OK
