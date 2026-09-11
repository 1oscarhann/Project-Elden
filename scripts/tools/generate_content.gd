extends Node

## Authoring tool. Writes the vertical slice's content into data/ as .tres.
##
##   godot --headless --path . res://scripts/tools/generate_content.tscn
##
## Run as a SCENE, not with --script: a --script MainLoop never registers the
## autoload globals, so any script referencing GameState or BattleManager fails
## to compile, load() hands back null, and the generated scene silently loses
## it — which is why _require_script() exists.
##
## Content normally lives as hand-edited .tres in the editor. This exists so
## the slice's starting set is reproducible and reviewable as code, and so a
## retune is a diff rather than twenty clicks.

const MOVE_DIR := "res://data/moves"
const ENEMY_DIR := "res://data/enemies"
const ITEM_DIR := "res://data/items"
const PARTY_DIR := "res://data/party"
const ENCOUNTER_DIR := "res://data/encounters"


func _ready() -> void:
	for dir in [MOVE_DIR, ENEMY_DIR, ITEM_DIR, PARTY_DIR, ENCOUNTER_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	var moves := _write_moves()
	var items := _write_items()
	_write_party(moves)
	var enemies := _write_enemies(moves)
	_write_encounters(enemies)

	print("generated %d moves, %d items, %d enemies" % [
		moves.size(), items.size(), enemies.size(),
	])
	get_tree().quit()


func _save(res: Resource, path: String) -> Resource:
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		push_error("failed to save %s (%d)" % [path, err])
	res.take_over_path(path)
	return res


func _move(
	id: String, name: String, type: StringName, power: int, sp: int, description: String,
	effect: MoveData.Effect = MoveData.Effect.DAMAGE,
	target: MoveData.Target = MoveData.Target.ONE_ENEMY
) -> MoveData:
	var m := MoveData.new()
	m.id = StringName(id)
	m.display_name = name
	m.type = type
	m.power = power
	m.sp_cost = sp
	m.description = description
	m.effect = effect
	m.target = target
	return _save(m, "%s/%s.tres" % [MOVE_DIR, id]) as MoveData


func _write_moves() -> Dictionary:
	var out: Dictionary = {}
	# Type wheel: fire > ice > wind > fire, shock > wind, light <-> dark.
	out["cleave"] = _move("cleave", "Cleave", &"physical", 30, 4, "A heavy two-handed swing.")
	out["ember"] = _move("ember", "Ember", &"fire", 28, 5, "A gout of flame. Melts ice.")
	out["frost"] = _move("frost", "Frost", &"ice", 28, 5, "Biting cold. Grounds the wind.")
	out["gale"] = _move("gale", "Gale", &"wind", 28, 5, "A cutting wind. Smothers fire.")
	out["jolt"] = _move("jolt", "Jolt", &"shock", 28, 5, "A sharp arc. Shreds wind.")
	out["radiance"] = _move("radiance", "Radiance", &"light", 34, 8, "Clean light. Burns the dark.")
	out["mend"] = _move(
		"mend", "Mend", &"light", 34, 6, "Closes your wounds.",
		MoveData.Effect.HEAL, MoveData.Target.SELF
	)

	out["cinder"] = _move("cinder", "Cinder", &"fire", 22, 4, "A spit of flame.")
	out["chill"] = _move("chill", "Chill", &"ice", 22, 4, "A creeping frost.")
	out["buffet"] = _move("buffet", "Buffet", &"wind", 22, 4, "A battering gust.")
	out["ruin"] = _move("ruin", "Ruin", &"dark", 36, 7, "Unmaking, given a shape.")
	out["crush"] = _move("crush", "Crush", &"physical", 32, 5, "Bearing down with full weight.")
	return out


func _write_items() -> Dictionary:
	var out: Dictionary = {}
	var potion := ItemData.new()
	potion.id = &"potion"
	potion.display_name = "Potion"
	potion.description = "Restores 40 HP."
	potion.effect = ItemData.Effect.HEAL_HP
	potion.amount = 40
	potion.price = 60
	out["potion"] = _save(potion, "%s/potion.tres" % ITEM_DIR)

	var ether := ItemData.new()
	ether.id = &"ether"
	ether.display_name = "Ether"
	ether.description = "Restores 18 SP."
	ether.effect = ItemData.Effect.HEAL_SP
	ether.amount = 18
	ether.price = 120
	out["ether"] = _save(ether, "%s/ether.tres" % ITEM_DIR)
	return out


func _write_party(moves: Dictionary) -> void:
	var hero := PartyMemberData.new()
	hero.id = &"hero"
	hero.display_name = "Wanderer"
	hero.level = 1
	hero.max_hp = 46
	hero.max_sp = 20
	hero.attack = 14
	hero.defense = 11
	hero.speed = 12
	hero.defend_type = &"physical"
	hero.moves = [moves["cleave"], moves["ember"]] as Array[MoveData]
	hero.hp_growth = 7
	hero.sp_growth = 3
	hero.attack_growth = 2
	hero.defense_growth = 2
	hero.speed_growth = 1
	# Radiance at 3 is the boss key — the Warden is only weak to light, so the
	# gate is gated on levelling, not on grinding gold.
	hero.learnset = {
		2: moves["frost"],
		3: moves["radiance"],
		4: moves["gale"],
		5: moves["mend"],
	}
	_save(hero, "%s/hero.tres" % PARTY_DIR)


func _enemy(
	id: String, name: String, level: int, hp: int, sp: int, atk: int, def_: int, spd: int,
	defend_type: StringName, enemy_moves: Array[MoveData], xp: int, gold: int, colour: Color,
	boss: bool = false
) -> EnemyData:
	var e := EnemyData.new()
	e.id = StringName(id)
	e.display_name = name
	e.level = level
	e.max_hp = hp
	e.max_sp = sp
	e.attack = atk
	e.defense = def_
	e.speed = spd
	e.defend_type = defend_type
	e.moves = enemy_moves
	e.xp_reward = xp
	e.gold_reward = gold
	e.placeholder_color = colour
	e.is_boss = boss
	e.aggression = 0.85 if boss else 0.7
	return _save(e, "%s/%s.tres" % [ENEMY_DIR, id]) as EnemyData


func _write_enemies(moves: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	out["frostbit"] = _enemy(
		"frostbit", "Frostbit", 1, 34, 12, 11, 9, 8, &"ice",
		[moves["chill"]] as Array[MoveData], 14, 12, Color(0.45, 0.75, 0.95)
	)
	out["emberling"] = _enemy(
		"emberling", "Emberling", 2, 30, 12, 13, 8, 13, &"fire",
		[moves["cinder"]] as Array[MoveData], 16, 14, Color(0.95, 0.45, 0.25)
	)
	out["gustling"] = _enemy(
		"gustling", "Gustling", 2, 28, 14, 12, 10, 16, &"wind",
		[moves["buffet"]] as Array[MoveData], 18, 16, Color(0.6, 0.9, 0.6)
	)
	out["warden"] = _enemy(
		"warden", "Warden of the First Gate", 5, 150, 40, 19, 15, 11, &"dark",
		[moves["ruin"], moves["crush"]] as Array[MoveData], 140, 200,
		Color(0.35, 0.2, 0.5), true
	)
	return out


func _write_encounters(enemies: Dictionary) -> void:
	var table := EncounterTable.new()
	table.zone_id = &"zone_01"
	table.encounters = [
		enemies["frostbit"], enemies["emberling"], enemies["gustling"],
	] as Array[EnemyData]
	table.weights = [4, 3, 3] as Array[int]
	table.steps_per_encounter = 24
	table.boss = enemies["warden"]
	_save(table, "%s/zone_01.tres" % ENCOUNTER_DIR)
