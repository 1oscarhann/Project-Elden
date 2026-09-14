class_name Animal
extends CharacterBody2D

## A passive, huntable animal.
##
## All of its character comes from an exported AnimalData, so this script never
## learns what a hare is. There is no combat here in either direction: it has no
## attack, and the only thing that can happen to it is being hunted.
##
## Movement goes through a NavigationAgent2D against the navigation mesh the
## island's TileMapLayer bakes from its land tiles. That mesh has no water in
## it, so an animal cannot path into the sea and get stuck on the shoreline —
## which is the wall-hugging jank the phase spec asks us to avoid.

signal died(data: AnimalData)

enum State { REST, WANDER, FLEE, DEAD }

## Close enough to a wander target to call it arrived.
const ARRIVE_EPSILON := 4.0
## Candidate wander points to try before giving up for this rest.
const WANDER_ATTEMPTS := 8
## How far a candidate may be dragged when snapped to the navigation mesh
## before we treat it as off-mesh entirely.
const WANDER_TOLERANCE := 20.0
## Seconds of pushing without getting anywhere before an animal gives up on its
## current target and picks another.
const STUCK_SECONDS := 0.7
## Below this much progress per second, it is not making headway.
const STUCK_SPEED := 6.0
## Seconds the corpse lies there before fading, so a kill reads as an event.
const LINGER_SECONDS := 0.9
const FADE_SECONDS := 0.5
## How long the hurt clip holds before the movement animation takes over again.
const HURT_SECONDS := 0.25

@export var data: AnimalData
@export_group("Feel")
## Camera trauma per hit. Gentler than chopping a tree — this is not a fight.
@export_range(0.0, 1.0) var shake_per_hit := 0.14

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _shadow: Sprite2D = $Shadow
@onready var _agent: NavigationAgent2D = $Agent
@onready var _detector: Area2D = $Detector
@onready var _detector_shape: CollisionShape2D = $Detector/CollisionShape2D
@onready var _reach: Area2D = $Reach
@onready var _puff: CPUParticles2D = $Puff

var _state := State.REST
var _facing := Vector2.DOWN
var _current_anim := ""
var _rest_left := 0.0
var _flee_left := 0.0
var _hits := 0
var _hurt_left := 0.0
var _stuck_time := 0.0
var _last_position := Vector2.ZERO
var _player_in_reach := false
var _threat: Node2D
var _rng := RandomNumberGenerator.new()
## Where it started, so it ambles around a home patch instead of drifting off.
var _home := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	if data == null:
		push_error("Animal has no AnimalData assigned.")
		set_physics_process(false)
		return
	_home = global_position
	_sprite.sprite_frames = data.sprite_frames
	_sprite.offset = data.sprite_offset
	_shadow.scale = data.shadow_scale
	_puff.color = data.puff_colour
	var circle := CircleShape2D.new()
	circle.radius = data.detection_radius
	_detector_shape.shape = circle
	_detector.body_entered.connect(_on_seen)
	_detector.body_exited.connect(_on_lost)
	_reach.body_entered.connect(_on_reach_entered)
	_reach.body_exited.connect(_on_reach_exited)
	_last_position = global_position
	_rest(_rng.randf_range(0.2, 1.6))


func is_alive() -> bool:
	return _state != State.DEAD


# --- hunting -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_reach and is_alive() and event.is_action_pressed("interact"):
		hit()
		get_viewport().set_input_as_handled()


## One swing. Returns true when this swing brought the animal down.
func hit() -> bool:
	if not is_alive():
		return false
	# The player is told to swing by group, so nothing here holds a reference
	# to them — the same arrangement harvestables use.
	get_tree().call_group("player", "swing", global_position - Vector2(0, 6))
	get_tree().call_group(PlayerCamera.GROUP, "add_trauma", shake_per_hit)
	_puff.restart()
	_puff.emitting = true
	_hits += 1
	if _hits < data.hits_required:
		# Being hit is also the loudest possible reason to run.
		_startle(_threat)
		_play("hurt")
		_hurt_left = HURT_SECONDS
		return false
	_die()
	return true


func _die() -> void:
	_state = State.DEAD
	velocity = Vector2.ZERO
	_award_drops()
	_reach.monitoring = false
	_detector.monitoring = false
	# The body stops colliding immediately so it cannot block the player who
	# just walked up to it.
	collision_layer = 0
	collision_mask = 0
	_play("death")
	died.emit(data)
	var tween := create_tween()
	tween.tween_interval(LINGER_SECONDS)
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)


func _award_drops() -> void:
	for drop in data.drops:
		if drop == null or drop.item_id.is_empty():
			continue
		var count := drop.roll(_rng)
		if count <= 0:
			continue  # An entry whose chance did not come up.
		# Overflow is simply lost, as with harvesting: a cozy game does not
		# refuse a kill because the bag is full.
		Inventory.add_item(drop.item_id, count)


# --- state machine -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _hurt_left > 0.0:
		_hurt_left -= delta
	match _state:
		State.DEAD:
			return
		State.REST:
			_rest_left -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			if _rest_left <= 0.0:
				_wander()
		State.WANDER:
			_steer(data.move_speed, delta)
			if _agent.is_navigation_finished():
				_rest(_rng.randf_range(data.rest_min, data.rest_max))
		State.FLEE:
			_flee_left -= delta
			if _flee_left <= 0.0:
				_rest(_rng.randf_range(0.4, 1.2))
			else:
				# Re-target as they close in, so it keeps running *away* rather
				# than sprinting to a spot the player is now standing on.
				if _agent.is_navigation_finished():
					_pick_escape()
				_steer(data.flee_speed, delta)
	move_and_slide()
	_check_stuck(delta)
	# Let the hurt clip finish rather than popping straight back to a run.
	if _hurt_left <= 0.0:
		_animate()


## ⚠️ The navigation mesh knows about water but NOT about trees, rocks or
## buildings — those are plain StaticBody2D colliders the mesh never saw. So an
## animal will happily path straight through a trunk, wedge against it with the
## engine reporting a perfectly reachable target, and push there forever.
##
## Watching for pushing-without-progress and re-targeting is what stops that
## being permanent. The proper fix is carving scenery out of the mesh, which
## `World._occupied` already has the data for.
func _check_stuck(delta: float) -> void:
	if _state != State.WANDER and _state != State.FLEE:
		_last_position = global_position
		_stuck_time = 0.0
		return
	var progress := global_position.distance_to(_last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	# Only counts as stuck if it is actually trying to move.
	if velocity.length() < STUCK_SPEED or progress > STUCK_SPEED:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time < STUCK_SECONDS:
		return
	_stuck_time = 0.0
	if _state == State.FLEE:
		_pick_escape()
	else:
		_wander()


## Walk the path the agent hands us. The agent owns *where*; we own *how fast*.
func _steer(speed: float, delta: float) -> void:
	if _agent.is_navigation_finished():
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		return
	var step := global_position.direction_to(_agent.get_next_path_position())
	if step.length_squared() > 0.001:
		_facing = step
	velocity = velocity.move_toward(step * speed, 500.0 * delta)


func _rest(seconds: float) -> void:
	_state = State.REST
	_rest_left = seconds


## ⚠️ The target must be ON the navigation mesh, not merely near home.
##
## Picking a raw point around home means an animal living near the shore aims
## into the sea most of the time. The agent then reports the path finished
## immediately, the animal rests, picks another sea target, and loops — stuck
## on the spot for good while looking idle rather than broken. Snapping each
## candidate to the mesh and rejecting the ones that land far from where we
## asked is what makes a coastal animal actually walk.
func _wander() -> void:
	_state = State.WANDER
	var map := _agent.get_navigation_map()
	for attempt in WANDER_ATTEMPTS:
		# Around home, not around here, so a long flee does not leave it homeless.
		var angle := _rng.randf() * TAU
		var reach := _rng.randf_range(data.wander_range * 0.3, data.wander_range)
		var want := _home + Vector2.RIGHT.rotated(angle) * reach
		if not map.is_valid():
			_target(want)
			return
		var landed := NavigationServer2D.map_get_closest_point(map, want)
		# Far from where we asked means the mesh does not reach there at all.
		if landed.distance_to(want) > WANDER_TOLERANCE:
			continue
		# And too close to here is not a walk worth taking.
		if landed.distance_to(global_position) < ARRIVE_EPSILON * 3.0:
			continue
		_target(landed)
		return
	# Genuinely hemmed in. Rest and try again rather than spin.
	_rest(_rng.randf_range(data.rest_min, data.rest_max))


func _startle(threat: Node2D) -> void:
	if not is_alive():
		return
	_threat = threat
	_flee_left = data.flee_memory
	if _state != State.FLEE:
		_state = State.FLEE
		_pick_escape()


## Run directly away from the threat. The agent then finds a real path there,
## which is what keeps it from sprinting into the sea or a cliff of trees.
func _pick_escape() -> void:
	var away := Vector2.RIGHT.rotated(_rng.randf() * TAU)
	if _threat != null and is_instance_valid(_threat):
		away = (global_position - _threat.global_position).normalized()
		# A little spread, so a herd does not move as one rigid block.
		away = away.rotated(_rng.randf_range(-0.5, 0.5))
	_target(global_position + away * data.detection_radius * 2.0)


func _target(point: Vector2) -> void:
	_agent.target_position = point


func _on_seen(body: Node2D) -> void:
	if body is Player:
		_startle(body)


func _on_lost(body: Node2D) -> void:
	if body == _threat:
		# Do not stop dead the instant they step outside the circle — keep
		# running for flee_memory seconds so escaping reads as escaping.
		_threat = null


func _on_reach_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_reach = true


func _on_reach_exited(body: Node2D) -> void:
	if body is Player:
		_player_in_reach = false


# --- animation ---------------------------------------------------------------

func _animate() -> void:
	if velocity.length() < 2.0:
		_play("idle")
	elif _state == State.FLEE:
		_play("run")
	else:
		_play("walk")


func _play(state: String) -> void:
	var anim := "%s_%s" % [state, _direction_name(_facing)]
	if anim == _current_anim or not _sprite.sprite_frames.has_animation(anim):
		return
	_current_anim = anim
	_sprite.play(anim)


## Snap to one of the four facings the art has — the same rule the player uses.
func _direction_name(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"
