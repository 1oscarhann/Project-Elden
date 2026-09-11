class_name ContentDB
extends RefCounted

## Loads every content .tres once and indexes it by id.
##
## This is the payoff for pillar 2 (SPEC §2): adding an enemy, a move or an
## item is dropping a file into data/ — no registration, no code change.

const ENEMY_DIR := "res://data/enemies"
const MOVE_DIR := "res://data/moves"
const ITEM_DIR := "res://data/items"
const PARTY_DIR := "res://data/party"
const ENCOUNTER_DIR := "res://data/encounters"

static var _enemies: Dictionary = {}
static var _moves: Dictionary = {}
static var _items: Dictionary = {}
static var _party: Dictionary = {}
static var _encounters: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_enemies = _load_dir(ENEMY_DIR)
	_moves = _load_dir(MOVE_DIR)
	_items = _load_dir(ITEM_DIR)
	_party = _load_dir(PARTY_DIR)
	_encounters = _load_dir(ENCOUNTER_DIR)
	_loaded = true


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func enemy(id: StringName) -> EnemyData:
	ensure_loaded()
	return _enemies.get(id)


static func move(id: StringName) -> MoveData:
	ensure_loaded()
	return _moves.get(id)


static func item(id: StringName) -> ItemData:
	ensure_loaded()
	return _items.get(id)


## Returns a fresh deep copy — the caller owns it and will mutate its level.
static func party_member(id: StringName) -> PartyMemberData:
	ensure_loaded()
	var template: PartyMemberData = _party.get(id)
	if template == null:
		return null
	return template.duplicate(true) as PartyMemberData


static func encounter_table(zone_id: StringName) -> EncounterTable:
	ensure_loaded()
	return _encounters.get(zone_id)


static func all_enemies() -> Array:
	ensure_loaded()
	return _enemies.values()


static func all_items() -> Array:
	ensure_loaded()
	return _items.values()


static func _load_dir(path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ContentDB: missing content directory %s" % path)
		return out

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# Exported builds rename .tres to .tres.remap; strip it back off.
			var clean: String = file_name.trim_suffix(".remap")
			if clean.get_extension() == "tres":
				var res: Resource = ResourceLoader.load(path.path_join(clean))
				if res != null and &"id" in res:
					out[res.get(&"id")] = res
				elif res is EncounterTable:
					out[(res as EncounterTable).zone_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	return out
