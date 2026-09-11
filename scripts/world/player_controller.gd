class_name PlayerController
extends CharacterBody3D

## Overworld movement (SPEC §9 step 1). Camera-relative WASD on a
## CharacterBody3D, with a SpringArm3D chase camera so the arm handles wall
## collision for free.

signal distance_walked(metres: float)

const SPEED := 5.5
const ACCELERATION := 14.0
const FRICTION := 18.0
const ROTATION_SPEED := 12.0
const JUMP_VELOCITY := 4.8

## Degrees per second at full stick / mouse-look.
const CAMERA_SPEED := 140.0
const MOUSE_SENSITIVITY := 0.006
const PITCH_MIN := -50.0
const PITCH_MAX := 20.0

@export var camera_pivot_path: NodePath = ^"CameraPivot"
@export var model_path: NodePath = ^"Model"
@export var control_enabled: bool = true

var _pivot: Node3D
var _model: Node3D
var _spring: SpringArm3D
var _gravity: float = 9.8


func _ready() -> void:
	_pivot = get_node_or_null(camera_pivot_path)
	_model = get_node_or_null(model_path)
	if _pivot != null:
		_spring = _pivot.get_node_or_null(^"SpringArm3D")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled or _pivot == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_pivot.rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		_apply_pitch(-motion.relative.y * MOUSE_SENSITIVITY)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if not control_enabled:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_update_camera(delta)

	var input := Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	var direction := _camera_relative(input)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() > 0.01:
		horizontal = horizontal.move_toward(direction * SPEED, ACCELERATION * delta)
		_face(direction, delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var before := global_position
	move_and_slide()

	# Encounter pacing is driven by distance actually travelled, not by frames
	# held down — so walking into a wall never rolls an encounter.
	if is_on_floor():
		var moved: float = Vector2(
			global_position.x - before.x, global_position.z - before.z
		).length()
		if moved > 0.0001:
			distance_walked.emit(moved)


func _camera_relative(input: Vector2) -> Vector3:
	if _pivot == null:
		return Vector3(input.x, 0.0, input.y)
	var basis := _pivot.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	return (right * input.x + forward * input.y).normalized()


func _face(direction: Vector3, delta: float) -> void:
	if _model == null:
		return
	var target := atan2(direction.x, direction.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, target, ROTATION_SPEED * delta)


func _update_camera(delta: float) -> void:
	if _pivot == null:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look.length_squared() < 0.01:
		return
	_pivot.rotate_y(-deg_to_rad(look.x * CAMERA_SPEED * delta))
	_apply_pitch(-deg_to_rad(look.y * CAMERA_SPEED * delta))


func _apply_pitch(amount: float) -> void:
	if _spring == null:
		return
	_spring.rotation.x = clampf(
		_spring.rotation.x + amount, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX)
	)
