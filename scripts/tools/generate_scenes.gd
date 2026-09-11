extends Node

## Authoring tool. Builds World.tscn and Battle.tscn.
##
##   godot --headless --path . res://scripts/tools/generate_scenes.tscn
##
## Run as a SCENE, not with --script: a --script MainLoop never registers the
## autoload globals, so any script referencing GameState or BattleManager fails
## to compile, load() hands back null, and the generated scene silently loses
## it — which is why _require_script() exists.
##
## Generated rather than hand-written so the greybox is reproducible and the
## node wiring is reviewable. Once the slice proves out, the zone becomes a
## hand-built scene and this only regenerates Battle.tscn.

const SCENE_DIR := "res://scenes"
const GROUND_SIZE := 70.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SCENE_DIR)
	_write_battle()
	_write_world()
	print("scenes written")
	get_tree().quit()


## load() returning null here is the single most expensive failure mode in
## this file: the scene still packs, just without the script, and nothing
## complains until something far away misbehaves.
func _require_script(path: String) -> Script:
	var script: Script = load(path) as Script
	if script == null:
		push_error("TOOL ABORT: could not load %s — scene would be written without it" % path)
		get_tree().quit(1)
	return script


## A node is only saved into a PackedScene if it's owned by the scene root —
## and the root itself must own nothing, hence the skip.
func _own(node: Node, root: Node) -> Node:
	if node != root:
		node.owner = root
	for child in node.get_children():
		_own(child, root)
	return node


func _pack(root: Node, path: String) -> void:
	var scene := PackedScene.new()
	var err: int = scene.pack(root)
	if err != OK:
		push_error("pack failed for %s (%d)" % [path, err])
		return
	err = ResourceSaver.save(scene, path)
	if err != OK:
		push_error("save failed for %s (%d)" % [path, err])
	root.free()


func _material(colour: Color, rough: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = rough
	return mat


func _write_battle() -> void:
	# Battle.tscn is deliberately almost empty: the stage and the UI are built
	# at runtime, so there is nothing here to drift out of sync with the code.
	var root := Node3D.new()
	root.name = "Battle"
	root.set_script(_require_script("res://scripts/battle/battle_scene.gd"))
	_pack(root, "%s/Battle.tscn" % SCENE_DIR)


func _write_world() -> void:
	var root := Node3D.new()
	root.name = "World"
	root.set_script(_require_script("res://scripts/world/world.gd"))

	root.add_child(_environment())
	root.add_child(_sun())
	root.add_child(_ground())
	for block in _scenery():
		root.add_child(block)
	root.add_child(_player())
	root.add_child(_field())
	root.add_child(_boss_gate())

	_own(root, root)
	_pack(root, "%s/World.tscn" % SCENE_DIR)


func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_horizon_color = Color(0.55, 0.58, 0.62)
	material.ground_horizon_color = Color(0.3, 0.3, 0.33)
	sky.sky_material = material
	env.sky = sky
	# No real-time GI: web budget (SPEC §8). Ambient comes from the sky only.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6

	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = env
	return node


func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	return sun


func _ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	mesh_node.mesh = plane
	mesh_node.material_override = _material(Color(0.29, 0.35, 0.28))
	body.add_child(mesh_node)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape_node)
	return body


func _scenery() -> Array[StaticBody3D]:
	# Greybox blockers: something to walk around, and a wall for the SpringArm
	# to actually collide with so the chase camera gets tested.
	var layout: Array = [
		[Vector3(-9.0, 1.5, -6.0), Vector3(3.0, 3.0, 3.0)],
		[Vector3(7.0, 1.0, -11.0), Vector3(6.0, 2.0, 2.0)],
		[Vector3(12.0, 2.0, 4.0), Vector3(2.0, 4.0, 9.0)],
		[Vector3(-13.0, 1.0, 9.0), Vector3(4.0, 2.0, 4.0)],
	]
	var out: Array[StaticBody3D] = []
	for i in layout.size():
		var body := StaticBody3D.new()
		body.name = "Block%d" % i
		body.position = layout[i][0]

		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Mesh"
		var box_mesh := BoxMesh.new()
		box_mesh.size = layout[i][1]
		mesh_node.mesh = box_mesh
		mesh_node.material_override = _material(Color(0.42, 0.4, 0.38))
		body.add_child(mesh_node)

		var shape_node := CollisionShape3D.new()
		shape_node.name = "Collision"
		var box_shape := BoxShape3D.new()
		box_shape.size = layout[i][1]
		shape_node.shape = box_shape
		body.add_child(shape_node)
		out.append(body)
	return out


func _player() -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(_require_script("res://scripts/world/player_controller.gd"))
	player.position = Vector3(0.0, 1.0, 6.0)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	shape_node.shape = capsule
	player.add_child(shape_node)

	var model := Node3D.new()
	model.name = "Model"
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "Body"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = 1.8
	capsule_mesh.radius = 0.4
	body_mesh.mesh = capsule_mesh
	body_mesh.material_override = _material(Color(0.85, 0.82, 0.7))
	model.add_child(body_mesh)

	# A nub on the front so facing is readable without an animated model.
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.2, 0.2, 0.4)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 0.35, 0.45)
	nose.material_override = _material(Color(0.9, 0.35, 0.3))
	model.add_child(nose)
	player.add_child(model)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position = Vector3(0.0, 1.4, 0.0)
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.spring_length = 5.5
	spring.margin = 0.3
	spring.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	spring.add_child(camera)
	pivot.add_child(spring)
	player.add_child(pivot)
	return player


func _field() -> Area3D:
	var area := Area3D.new()
	area.name = "EncounterField"
	area.set_script(_require_script("res://scripts/world/encounter_zone.gd"))
	area.set(&"table", load("res://data/encounters/zone_01.tres"))
	area.monitoring = true

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE - 6.0, 6.0, GROUND_SIZE - 6.0)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, 3.0, 0.0)
	area.add_child(shape_node)
	return area


func _boss_gate() -> Area3D:
	var gate := Area3D.new()
	gate.name = "BossGate"
	gate.set_script(_require_script("res://scripts/world/boss_gate.gd"))
	gate.set(&"table", load("res://data/encounters/zone_01.tres"))
	gate.position = Vector3(0.0, 1.5, -26.0)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 3.0, 3.0)
	shape_node.shape = box
	gate.add_child(shape_node)

	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var arch := BoxMesh.new()
	arch.size = Vector3(8.0, 3.0, 0.5)
	marker.mesh = arch
	marker.material_override = _material(Color(0.35, 0.2, 0.5), 0.4)
	gate.add_child(marker)
	return gate
