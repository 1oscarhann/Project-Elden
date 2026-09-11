extends GutTest

## The stage and the whole combat UI are built procedurally, so nothing catches
## a bad node setup except actually instantiating the scenes.

var _spawned: Array[Node] = []


func before_each():
	GameState.new_game()
	BattleManager.turn_delay = 0.0


func after_each():
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned = []
	await get_tree().process_frame
	GameState.new_game()


func _spawn(path: String) -> Node:
	var scene: PackedScene = load(path)
	assert_not_null(scene, "%s loads" % path)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	_spawned.append(node)
	get_tree().root.add_child(node)
	return node


func test_the_world_scene_boots_with_its_script():
	var world: Node = _spawn("res://scenes/World.tscn")
	await get_tree().process_frame
	assert_not_null(world.get_script(), "the world root kept its script")


func test_the_world_has_a_player_with_a_chase_camera():
	var world: Node = _spawn("res://scenes/World.tscn")
	await get_tree().process_frame

	var player: Node = world.get_node_or_null(^"Player")
	assert_true(player is PlayerController, "the player is a PlayerController")
	assert_not_null(
		world.get_node_or_null(^"Player/CameraPivot/SpringArm3D/Camera3D"),
		"the SpringArm chase camera is wired up"
	)
	assert_not_null(world.get_node_or_null(^"Player/Model"), "the player has a model node")
	assert_not_null(world.get_node_or_null(^"Player/Collision"), "the player has a collider")


func test_the_player_is_a_3d_character_body():
	# Guards the 3D constraint: this must never quietly become a 2D project.
	var world: Node = _spawn("res://scenes/World.tscn")
	await get_tree().process_frame
	assert_true(world is Node3D, "the world root is 3D")
	assert_true(world.get_node(^"Player") is CharacterBody3D, "the player is a CharacterBody3D")


func test_the_world_has_its_encounter_triggers():
	var world: Node = _spawn("res://scenes/World.tscn")
	await get_tree().process_frame

	var field: Node = world.get_node_or_null(^"EncounterField")
	assert_true(field is EncounterZone, "the encounter field kept its script")
	assert_not_null(field.table, "the encounter field has a table assigned")

	var gate: Node = world.get_node_or_null(^"BossGate")
	assert_true(gate is BossGate, "the boss gate kept its script")
	assert_not_null(gate.table, "the boss gate has a table assigned")


func test_the_battle_scene_boots_and_builds_its_ui():
	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])
	var battle: Node = _spawn("res://scenes/Battle.tscn")
	await get_tree().process_frame

	assert_not_null(battle.get_script(), "the battle root kept its script")

	var has_ui: bool = false
	for child in battle.get_children():
		if child is BattleUI:
			has_ui = true
	assert_true(has_ui, "the battle scene builds its UI")


func test_the_battle_scene_consumes_the_queued_encounter():
	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])
	_spawn("res://scenes/Battle.tscn")
	await get_tree().process_frame

	assert_eq(BattleManager.enemies.size(), 1, "the queued foe entered the fight")
	assert_eq(BattleManager.phase, Combat.Phase.PLAYER, "the fight opens on the player")
	assert_eq(
		BattleManager.take_pending_encounter().size(), 0,
		"the pending encounter was cleared"
	)


func test_the_battle_scene_spawns_a_body_per_enemy():
	BattleManager.queue_encounter(
		[ContentDB.enemy(&"frostbit"), ContentDB.enemy(&"gustling")] as Array[EnemyData]
	)
	var battle: Node = _spawn("res://scenes/Battle.tscn")
	await get_tree().process_frame

	var meshes: int = 0
	for child in battle.get_children():
		if child is MeshInstance3D and child.mesh is CapsuleMesh:
			meshes += 1
	assert_eq(meshes, 2, "one body per enemy")


func test_the_battle_scene_has_a_camera_and_a_light():
	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])
	var battle: Node = _spawn("res://scenes/Battle.tscn")
	await get_tree().process_frame

	var has_camera: bool = false
	var has_light: bool = false
	for child in battle.get_children():
		if child is Camera3D:
			has_camera = true
		if child is DirectionalLight3D:
			has_light = true
	assert_true(has_camera, "the battle stage has a camera")
	assert_true(has_light, "the battle stage has a light")
