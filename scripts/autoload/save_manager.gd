extends Node

## Autoload. Serialise/deserialise GameState, and talk to the backend (SPEC §5, §7).
##
## Local disk saves come first (build order step 5). The Neon/FastAPI path is
## step 7 and must never block the game booting — see docs/REVIEW.md on Render
## free-tier cold starts.

signal save_completed(slot_index: int, ok: bool)
signal load_completed(slot_index: int, ok: bool)

const MAX_BLOB_BYTES := 256 * 1024


func save_local(_slot_index: int) -> void:
	push_error("SaveManager.save_local() not implemented (build order step 5)")


func load_local(_slot_index: int) -> void:
	push_error("SaveManager.load_local() not implemented (build order step 5)")
