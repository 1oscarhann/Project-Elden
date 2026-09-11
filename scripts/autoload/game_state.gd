extends Node

## Autoload. The single source of truth for everything a save file contains
## (SPEC §5): party, inventory, gold, story flags, current zone.
##
## Rule: the overworld scene owns nothing durable. Player position and zone
## state are written here BEFORE swapping to Battle.tscn and read back after,
## because World.tscn is unloaded during combat (SPEC §5).

signal gold_changed(amount: int)
signal flag_changed(flag: StringName, value: Variant)
signal party_member_leveled(member: PartyMemberData, new_level: int, learned: Array)
signal inventory_changed()

## XP needed to go from level n to n+1.
const XP_CURVE_BASE := 24
const XP_CURVE_EXPONENT := 1.45

var party: Array[PartyMemberData] = []
## Runtime HP/SP carried between fights, keyed by member id.
var vitals: Dictionary = {}
var experience: Dictionary = {}

var inventory: Dictionary = {}
var gold: int = 0
var story_flags: Dictionary = {}

var current_zone: StringName = &"zone_01"
var player_position: Vector3 = Vector3.ZERO
var player_facing: float = 0.0


func _ready() -> void:
	if party.is_empty():
		new_game()


func new_game() -> void:
	party.clear()
	vitals.clear()
	experience.clear()
	inventory.clear()
	story_flags.clear()
	gold = 150
	current_zone = &"zone_01"
	player_position = Vector3.ZERO
	player_facing = 0.0

	var starter := ContentDB.party_member(&"hero")
	if starter != null:
		add_party_member(starter)

	add_item(&"potion", 3)
	add_item(&"ether", 1)


func add_party_member(member: PartyMemberData) -> void:
	party.append(member)
	vitals[member.id] = {"hp": member.max_hp, "sp": member.max_sp}
	if not experience.has(member.id):
		experience[member.id] = 0


## Stat blocks with live HP/SP applied, ready to hand to BattleManager.
func battle_party() -> Array[BattlerData]:
	var out: Array[BattlerData] = []
	for member in party:
		out.append(member)
	return out


func store_vitals(battlers: Array) -> void:
	for b in battlers:
		if b is Battler and b.is_player_side:
			vitals[b.data.id] = {"hp": b.hp, "sp": b.sp}


func restore_vitals_into(battlers: Array) -> void:
	for b in battlers:
		if b is Battler and b.is_player_side and vitals.has(b.data.id):
			var v: Dictionary = vitals[b.data.id]
			b.hp = clampi(int(v.get("hp", b.data.max_hp)), 0, b.data.max_hp)
			b.sp = clampi(int(v.get("sp", b.data.max_sp)), 0, b.data.max_sp)


# --- Progression (SPEC §6) --------------------------------------------------

static func xp_for_level(level: int) -> int:
	return int(round(XP_CURVE_BASE * pow(float(maxi(1, level)), XP_CURVE_EXPONENT)))


func award_xp(amount: int) -> void:
	for member in party:
		experience[member.id] = int(experience.get(member.id, 0)) + amount
		while int(experience[member.id]) >= xp_for_level(member.level):
			experience[member.id] = int(experience[member.id]) - xp_for_level(member.level)
			_level_up(member)


func _level_up(member: PartyMemberData) -> void:
	member.level += 1
	member.max_hp += member.hp_growth
	member.max_sp += member.sp_growth
	member.attack += member.attack_growth
	member.defense += member.defense_growth
	member.speed += member.speed_growth

	var learned: Array = []
	if member.learnset.has(member.level):
		var move: MoveData = member.learnset[member.level]
		if move != null and not member.moves.has(move):
			member.moves.append(move)
			learned.append(move)

	# Level-ups top you up — it's the pacing release valve between fights.
	vitals[member.id] = {"hp": member.max_hp, "sp": member.max_sp}
	party_member_leveled.emit(member, member.level, learned)


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


# --- Inventory --------------------------------------------------------------

func add_item(id: StringName, count: int = 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + count
	inventory_changed.emit()


func consume_item(id: StringName, count: int = 1) -> bool:
	var have: int = int(inventory.get(id, 0))
	if have < count:
		return false
	if have == count:
		inventory.erase(id)
	else:
		inventory[id] = have - count
	inventory_changed.emit()
	return true


func item_count(id: StringName) -> int:
	return int(inventory.get(id, 0))


# --- Flags ------------------------------------------------------------------

func set_flag(flag: StringName, value: Variant = true) -> void:
	story_flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: StringName, fallback: Variant = false) -> Variant:
	return story_flags.get(flag, fallback)


# --- Serialisation (SPEC §7: one JSON blob, don't over-normalise) -----------

func to_dict() -> Dictionary:
	var party_out: Array = []
	for member in party:
		party_out.append({
			"id": String(member.id),
			"level": member.level,
			"xp": int(experience.get(member.id, 0)),
			"hp": int(vitals.get(member.id, {}).get("hp", member.max_hp)),
			"sp": int(vitals.get(member.id, {}).get("sp", member.max_sp)),
		})

	var inventory_out: Dictionary = {}
	for id in inventory:
		inventory_out[String(id)] = inventory[id]

	var flags_out: Dictionary = {}
	for flag in story_flags:
		flags_out[String(flag)] = story_flags[flag]

	return {
		"version": SaveFormat.VERSION,
		"party": party_out,
		"inventory": inventory_out,
		"gold": gold,
		"flags": flags_out,
		"zone": String(current_zone),
		"position": [player_position.x, player_position.y, player_position.z],
		"facing": player_facing,
	}


func from_dict(data: Dictionary) -> bool:
	var version: int = int(data.get("version", 0))
	if version <= 0 or version > SaveFormat.VERSION:
		push_warning("GameState: rejected save blob, version %d" % version)
		return false

	party.clear()
	vitals.clear()
	experience.clear()
	inventory.clear()
	story_flags.clear()

	for entry in data.get("party", []):
		var member := ContentDB.party_member(StringName(entry.get("id", "")))
		if member == null:
			push_warning("GameState: save references unknown party member %s" % entry.get("id"))
			continue
		# Replay the growth curve rather than trusting stats from the blob —
		# the client is not authoritative and the curve may have been retuned.
		var target_level: int = maxi(1, int(entry.get("level", 1)))
		party.append(member)
		experience[member.id] = int(entry.get("xp", 0))
		while member.level < target_level:
			_level_up(member)
		vitals[member.id] = {
			"hp": clampi(int(entry.get("hp", member.max_hp)), 0, member.max_hp),
			"sp": clampi(int(entry.get("sp", member.max_sp)), 0, member.max_sp),
		}

	for id in data.get("inventory", {}):
		inventory[StringName(id)] = int(data["inventory"][id])
	for flag in data.get("flags", {}):
		story_flags[StringName(flag)] = data["flags"][flag]

	gold = int(data.get("gold", 0))
	current_zone = StringName(data.get("zone", "zone_01"))

	var pos: Array = data.get("position", [0, 0, 0])
	if pos.size() == 3:
		player_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	player_facing = float(data.get("facing", 0.0))

	gold_changed.emit(gold)
	inventory_changed.emit()
	return true
