extends Node

## Reads and writes the game's save files.
##
## Autoload. Saves are plain JSON in user://, one file per slot, and carry a
## format version so a later change can migrate an old file instead of
## crashing on it.
##
## The manager does not know what any system's state MEANS. Every participant
## exposes save_data() -> Dictionary and load_data(Dictionary), and this file
## only ever posts those dictionaries around. Adding a system to the save is a
## pair of methods on that system and one line here.

signal saved(slot: int)
signal loaded(slot: int)
signal save_failed(slot: int, reason: String)

## Bump this when the shape of a save changes, and handle the old shape in
## _migrate(). A file from the future is refused rather than half-read.
const FORMAT_VERSION := 1
const SLOT_COUNT := 3
const MAIN_SCENE := "res://scenes/main/Main.tscn"

## Data read from disk and waiting for a freshly loaded scene to apply it.
var _pending: Dictionary = {}


func save_path(slot: int) -> String:
	return "user://save_%02d.json" % clampi(slot, 0, SLOT_COUNT - 1)


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(save_path(slot))


## Writes the current session to disk. Returns false and emits save_failed if
## anything goes wrong, so a caller can say so rather than assume it worked.
func save_game(slot: int) -> bool:
	var world := _find_world()
	if world == null:
		save_failed.emit(slot, "no world in the scene")
		return false

	var data := {
		"version": FORMAT_VERSION,
		# Not read back — it is there so a save file is legible to a human and
		# so a slot list can show when it was made.
		"saved_at": Time.get_datetime_string_from_system(),
		"day_night": DayNight.save_data(),
		"game_state": GameState.save_data(),
		"inventory": Inventory.save_data(),
		"weather": Weather.save_data(),
		"world": world.save_data(),
		"player": _player_data(world),
	}

	var file := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "cannot write %s" % save_path(slot))
		return false
	# Indented on purpose: a save you can open and read is a save you can debug.
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	saved.emit(slot)
	return true


## Reads a slot without applying it — for the menu's "Day 4, 07:12" line.
## Returns an empty dictionary when the slot is missing or unreadable.
func read_save(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(save_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("SaveManager: slot %d is not a JSON object" % slot)
		return {}
	return _migrate(parsed as Dictionary, slot)


## One-line summary of a slot for the main menu.
func slot_summary(slot: int) -> String:
	var data := read_save(slot)
	if data.is_empty():
		return "Empty"
	var clock: Dictionary = data.get("day_night", {})
	var minutes := int(float(clock.get("time_of_day", 0.0)) * 24.0 * 60.0)
	return "Day %d   %02d:%02d" % [int(clock.get("day", 1)), minutes / 60, minutes % 60]


## Loads a slot by restarting the scene and applying the file to the fresh one.
##
## Restarting rather than patching the live scene is deliberate: a world that
## has been played in carries chopped trees, placed buildings and a wandering
## population, and unpicking all of that correctly is far more fragile than
## building it once from scratch.
func load_game(slot: int) -> bool:
	var data := read_save(slot)
	if data.is_empty():
		save_failed.emit(slot, "slot %d is empty or unreadable" % slot)
		return false
	_pending = data
	get_tree().change_scene_to_file(MAIN_SCENE)
	# change_scene_to_file is deferred to the end of the frame, so the new
	# scene's _ready has not run yet. Two frames is one to swap and one to
	# settle, which is also when the world has finished building.
	await get_tree().process_frame
	await get_tree().process_frame
	apply_data(_pending)
	_pending = {}
	loaded.emit(slot)
	return true


## Starts a brand new game: resets every autoload and reloads the scene.
## Without the resets, "New Game" from a session in progress would keep the old
## inventory and clock.
func new_game() -> void:
	_pending = {}
	Inventory.clear()
	DayNight.load_data({"time_of_day": DayNight.start_time_of_day, "day": 1})
	# The ONLY place the intro flag is cleared. Everywhere else — including a
	# save file too old to carry the key — defaults it to already-shown, so the
	# opening cannot replay itself at someone mid-playthrough.
	GameState.load_data({"intro_shown": false})
	get_tree().change_scene_to_file(MAIN_SCENE)


func delete_save(slot: int) -> bool:
	if not has_save(slot):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path(slot))) == OK


## Applies an already-read save to whatever scene is currently up. Public so a
## test can build a world and restore into it without a scene change.
func apply_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	DayNight.load_data(data.get("day_night", {}))
	GameState.load_data(data.get("game_state", {}))
	Inventory.load_data(data.get("inventory", {}))
	Weather.load_data(data.get("weather", {}))
	var world := _find_world()
	if world != null:
		world.load_data(data.get("world", {}))
		_restore_player(world, data.get("player", {}))


# --- internals --------------------------------------------------------------

## Where the player is, and which room they are standing in. Interiors are not
## restored as rooms: a save made inside a hut puts you back outside its door,
## which is a far smaller promise to keep than reconstructing a cached room.
func _player_data(world: World) -> Dictionary:
	var player := _find_player()
	if player == null:
		return {}
	var position: Vector2 = player.global_position
	# Standing in an interior means the position is off in a parked room slot,
	# which is meaningless on the island. Fall back to the spawn.
	var rooms := get_tree().get_nodes_in_group(RoomManager.GROUP)
	if not rooms.is_empty() and (rooms[0] as RoomManager).current_room() != world:
		position = world.entry_position()
	return {"x": position.x, "y": position.y}


func _restore_player(world: World, data: Dictionary) -> void:
	var player := _find_player()
	if player == null or data.is_empty():
		return
	player.global_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	player.velocity = Vector2.ZERO
	# Otherwise the camera glides across the island from wherever it was.
	get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")


func _find_world() -> World:
	var rooms := get_tree().get_nodes_in_group(RoomManager.GROUP)
	if rooms.is_empty():
		return null
	return (rooms[0] as RoomManager).get_node_or_null("World") as World


func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Player if not players.is_empty() else null


## Brings an older file up to the current format. There is only one version so
## far, so this is a version check — but the hook exists now, before there are
## saves in the wild that would otherwise have to be thrown away.
func _migrate(data: Dictionary, slot: int) -> Dictionary:
	var version := int(data.get("version", 0))
	if version == FORMAT_VERSION:
		return data
	if version > FORMAT_VERSION:
		push_error("SaveManager: slot %d was written by a newer version (%d)" % [slot, version])
		return {}
	push_warning("SaveManager: slot %d is format %d, expected %d" % [slot, version, FORMAT_VERSION])
	return data
