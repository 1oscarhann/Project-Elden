extends Node3D

## Battle.tscn root (SPEC §5). Loaded on encounter, unloaded after — combat
## never runs inside the overworld.
##
## Placeholder capsules stand in for models. That's deliberate: the slice is
## proving the fight is fun, and art is the thing most likely to eat the
## 30 MB budget (SPEC §8).

const WORLD_SCENE := "res://scenes/World.tscn"
const RETURN_DELAY := 1.6

@export var enemy_spacing: float = 2.2

var _ui: BattleUI
var _enemy_nodes: Dictionary = {}


func _ready() -> void:
	_build_stage()

	_ui = BattleUI.new()
	add_child(_ui)

	BattleManager.battle_finished.connect(_on_battle_finished)
	BattleManager.battler_died.connect(_on_battler_died)
	BattleManager.action_resolved.connect(_on_action_resolved)

	var foes: Array[EnemyData] = BattleManager.take_pending_encounter()
	if foes.is_empty():
		push_warning("Battle.tscn opened with no queued encounter; returning to world.")
		_return_to_world()
		return

	BattleManager.start_battle(GameState.battle_party(), foes)
	GameState.restore_vitals_into(BattleManager.player_party)
	_spawn_enemies(foes)


func _build_stage() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.2, 7.5)
	camera.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.1
	add_child(light)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _material(Color(0.16, 0.17, 0.22))
	add_child(floor_mesh)


func _spawn_enemies(foes: Array[EnemyData]) -> void:
	var start: float = -enemy_spacing * float(foes.size() - 1) * 0.5
	for i in foes.size():
		var foe: EnemyData = foes[i]
		var node := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = 2.4 if foe.is_boss else 1.8
		capsule.radius = 0.6 if foe.is_boss else 0.4
		node.mesh = capsule
		node.material_override = _material(foe.placeholder_color)
		node.position = Vector3(start + enemy_spacing * float(i), capsule.height * 0.5, -2.0)
		add_child(node)

		if i < BattleManager.enemies.size():
			_enemy_nodes[BattleManager.enemies[i]] = node


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	return material


func _on_action_resolved(line: String) -> void:
	# Remember what the player has learned about each enemy, so the target menu
	# can surface it next time. Scouting is only worth anything because a
	# weakness hit buys a turn (SPEC §6).
	if not line.contains("(WEAK!)"):
		return
	for battler in BattleManager.enemies:
		if line.contains(battler.display_name()):
			GameState.set_flag(BattleUI._weakness_flag(battler), true)


func _on_battler_died(who: Battler) -> void:
	var node: MeshInstance3D = _enemy_nodes.get(who)
	if node == null:
		return
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector3.ZERO, 0.35)
	tween.tween_callback(node.queue_free)


func _on_battle_finished(outcome: int, rewards: Dictionary) -> void:
	GameState.store_vitals(BattleManager.player_party)

	if outcome == Combat.Outcome.VICTORY:
		GameState.award_xp(int(rewards.get("xp", 0)))
		GameState.add_gold(int(rewards.get("gold", 0)))

	if outcome == Combat.Outcome.DEFEAT:
		_handle_defeat()

	await get_tree().create_timer(RETURN_DELAY).timeout
	_return_to_world()


func _handle_defeat() -> void:
	# Soft failure: reload the last local save rather than dumping a game-over
	# screen on someone who may not have saved for an hour.
	if SaveManager.slot_exists(0):
		SaveManager.load_local(0)
		return
	for member in GameState.party:
		GameState.vitals[member.id] = {"hp": member.max_hp, "sp": member.max_sp}
	GameState.player_position = Vector3.ZERO
	GameState.add_gold(-int(float(GameState.gold) * 0.1))


func _return_to_world() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)
