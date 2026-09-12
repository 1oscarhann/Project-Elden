class_name Player
extends CharacterBody2D

## Top-down player controller.
##
## Movement is plain 8-directional on a square grid — the isometric *look* comes
## purely from the angled art, never from the movement axes (CLAUDE.md rule 1).
## The art only has four facings, so diagonal input snaps to the nearest of them
## for animation purposes while the movement itself stays fully 8-way.

enum State { IDLE, WALK, RUN }

const STATE_NAMES := {State.IDLE: "idle", State.WALK: "walk", State.RUN: "run"}
## Below this speed with no input we are considered stopped.
const STOP_EPSILON := 1.0

@export_group("Movement")
## Pixels per second at a normal walk.
@export var walk_speed := 60.0
## Pixels per second while the "run" action is held.
@export var run_speed := 105.0
## Pixels per second squared while speeding up. Higher = snappier starts.
@export var acceleration := 700.0
## Pixels per second squared while slowing down. Higher = snappier stops.
@export var friction := 900.0

@onready var _sprite: AnimatedSprite2D = $Sprite

## Last non-zero input direction, so idle keeps facing wherever we stopped.
var _facing := Vector2.DOWN
var _state := State.IDLE
var _current_anim := ""


func _physics_process(delta: float) -> void:
	# get_vector() is already normalised, so diagonals are not faster.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("run")

	if input != Vector2.ZERO:
		_facing = input

	_apply_movement(input, running, delta)
	move_and_slide()

	_state = _resolve_state(input, running)
	_play_animation()


## Ease velocity toward the target rather than snapping to it, so starts and
## stops have weight. Both directions are delta-scaled.
func _apply_movement(input: Vector2, running: bool, delta: float) -> void:
	if input == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		return
	# Cold is a soft penalty: GameState.speed_factor() eases toward a floor, it
	# never reaches zero.
	var speed: float = (run_speed if running else walk_speed) * GameState.speed_factor()
	velocity = velocity.move_toward(input * speed, acceleration * delta)


## Note we stay in WALK while coasting to a halt, so the legs keep moving
## through the deceleration instead of popping to idle the frame input drops.
func _resolve_state(input: Vector2, running: bool) -> State:
	if input == Vector2.ZERO:
		return State.IDLE if velocity.length() < STOP_EPSILON else State.WALK
	return State.RUN if running else State.WALK


## Snap an arbitrary direction to one of the four directions the art has.
func _direction_name(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


func _play_animation() -> void:
	var anim := "%s_%s" % [STATE_NAMES[_state], _direction_name(_facing)]
	if anim == _current_anim:
		return  # Calling play() every frame would restart the animation.
	_current_anim = anim
	_sprite.play(anim)
