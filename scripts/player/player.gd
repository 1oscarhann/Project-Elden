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

@export_group("Feel")
## Distance walked between footsteps, in pixels. A stride, not a timer — so
## steps stay in sync whether you are walking, running or slowed by cold.
@export var stride := 16.0
## Sideways wobble, in pixels, when warmth is at zero. Scaled by chill().
@export var shiver_pixels := 0.7
@export var shiver_hz := 11.0

@export_group("Eating and drinking")
## How far from fresh water the player can drink, in tiles.
@export_range(1, 4) var drink_reach_tiles := 1
## Thirst restored by one drink. A pond is free and unlimited, so this is
## deliberately modest — the cost of water is the walk to it.
@export var drink_restore := 35.0
@export var drink_colour := Color(0.55, 0.78, 0.92, 0.85)
@export var eat_colour := Color(0.92, 0.72, 0.42, 0.85)

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _dust: CPUParticles2D = $Dust
## The dust's own colour, so a consume splash can borrow the emitter and hand it
## back rather than needing an emitter of its own.
@onready var _dust_colour: Color = $Dust.color

## Pixels left to walk before the next footstep.
var _stride_left := 0.0
## Running total for the shiver oscillation. Kept here rather than read from
## Time so it pauses with the game.
var _shiver_time := 0.0

## Set while the one-shot harvest swing plays, so the movement state machine
## does not stomp the animation mid-swing.
var _swinging := false

## Last non-zero input direction, so idle keeps facing wherever we stopped.
var _facing := Vector2.DOWN
var _state := State.IDLE
var _current_anim := ""


func _ready() -> void:
	# Joined by name so harvestables can ask for a swing without holding a
	# reference to the player.
	add_to_group("player")
	_sprite.animation_finished.connect(_on_animation_finished)


## Play the harvest chop, facing `target` if one is given. Ignored if already
## swinging, so mashing the key cannot restart the animation every frame.
func swing(target: Vector2 = Vector2.ZERO) -> void:
	if _swinging:
		return
	if target != Vector2.ZERO:
		var to_target := target - global_position
		if to_target.length_squared() > 1.0:
			_facing = to_target
	_swinging = true
	_current_anim = "chop_%s" % _direction_name(_facing)
	_sprite.play(_current_anim)


func _on_animation_finished() -> void:
	_swinging = false


## Use whatever is in the selected hotbar slot, or drink from fresh water.
##
## The player decides WHEN, the item's own data decides WHAT — nothing here
## knows about warmth tonics or how filling a roast is.
##
## ⚠️ Drinking is deliberately the LAST thing `interact` can mean. Harvestables,
## animals and the campfire all consume the event from their own Area2Ds first;
## this only ever sees an E that nothing else wanted, so standing at a pond
## never stops you chopping the tree beside it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _try_drink():
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("use_item"):
		return
	var id := Inventory.selected_item_id()
	if id.is_empty():
		return
	if GameState.consume(id):
		Inventory.remove_item(id, 1)
		Audio.play("eat")
		_splash(drink_colour if ItemDB.get_item(id).stat("thirst", 0.0) > 0.0 else eat_colour)
		get_viewport().set_input_as_handled()


## Drink if a freshwater cell is in reach. Returns false when there is none, or
## when there is nothing to gain, so the key falls through.
func _try_drink() -> bool:
	var rooms := get_tree().get_nodes_in_group(RoomManager.GROUP)
	if rooms.is_empty():
		return false
	var room := (rooms[0] as RoomManager).current_room()
	if room == null or not room.has_method("can_drink_at"):
		return false
	if not room.can_drink_at(global_position, drink_reach_tiles):
		return false
	if not GameState.drink(drink_restore):
		return false
	Audio.play("eat")
	_splash(drink_colour)
	return true


## A small burst in the colour of whatever was just consumed. Reuses the dust
## emitter rather than adding a second one — it is already a one-shot.
func _splash(colour: Color) -> void:
	_dust.color = colour
	_dust.restart()
	_dust.emitting = true
	# Put it back, or every footstep after this puffs the wrong colour.
	_dust.color = _dust_colour


func _physics_process(delta: float) -> void:
	# get_vector() is already normalised, so diagonals are not faster.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("run")

	if input != Vector2.ZERO:
		_facing = input

	_apply_movement(input, running, delta)
	move_and_slide()
	_footsteps(delta)
	_shiver(delta)

	_state = _resolve_state(input, running)
	# Moving cancels a swing; otherwise let the one-shot animation finish.
	if _swinging and input != Vector2.ZERO:
		_swinging = false
	if not _swinging:
		_play_animation()


## A puff of dust and a step sound every `stride` pixels travelled. Driven by
## distance rather than by the animation, because the animation is a looping
## SpriteFrames with no frame callbacks to hang this off.
func _footsteps(delta: float) -> void:
	var travelled := velocity.length() * delta
	if travelled < 0.01:
		# Reset part-way through a stride when they stop, so the next step
		# lands on setting off rather than immediately.
		_stride_left = stride * 0.4
		return
	_stride_left -= travelled
	if _stride_left > 0.0:
		return
	_stride_left = stride
	Audio.play("step", 0.14)
	_dust.restart()
	_dust.emitting = true


## A small horizontal tremble when cold, scaled by how cold. Applied to the
## SPRITE's offset, not the body: nudging the body would fight the physics and
## desync the shadow.
func _shiver(delta: float) -> void:
	var chill := GameState.chill()
	if chill <= 0.0:
		_sprite.offset.x = 0.0
		return
	_shiver_time += delta
	_sprite.offset.x = sin(_shiver_time * TAU * shiver_hz) * shiver_pixels * chill


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
