extends Node3D

## Overworld root (SPEC §5). Owns nothing durable: position and zone are read
## from GameState on entry and written back before the battle swap, because
## this scene is unloaded while Battle.tscn runs.

const BATTLE_SCENE := "res://scenes/Battle.tscn"

@export var player_path: NodePath = ^"Player"
@export var zone_id: StringName = &"zone_01"

var _player: PlayerController
var _zones: Array[EncounterZone] = []
var _triggers: Array[Node] = []
var _swapping: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path)
	GameState.current_zone = zone_id

	_collect_triggers(self)
	for trigger in _triggers:
		trigger.encounter_triggered.connect(_on_encounter)

	if _player != null:
		_player.distance_walked.connect(_on_distance_walked)
		_restore_player()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
	elif event.is_action_pressed(&"quick_save"):
		SaveManager.save_local(0)
		SaveManager.sync_up(0)


func _collect_triggers(node: Node) -> void:
	for child in node.get_children():
		if child is EncounterZone:
			_zones.append(child)
		if child.has_signal(&"encounter_triggered"):
			_triggers.append(child)
		_collect_triggers(child)


func _restore_player() -> void:
	if GameState.player_position != Vector3.ZERO:
		_player.global_position = GameState.player_position
	_player.rotation.y = GameState.player_facing


func _store_player() -> void:
	if _player == null:
		return
	GameState.player_position = _player.global_position
	GameState.player_facing = _player.rotation.y


func _on_distance_walked(metres: float) -> void:
	if _swapping:
		return
	for zone in _zones:
		zone.accumulate(metres)


func _on_encounter(foes: Array) -> void:
	if _swapping:
		return
	_swapping = true

	var typed: Array[EnemyData] = []
	for foe in foes:
		if foe is EnemyData:
			typed.append(foe)
	if typed.is_empty():
		_swapping = false
		return

	_store_player()
	if _player != null:
		_player.control_enabled = false

	BattleManager.queue_encounter(typed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(BATTLE_SCENE)
