class_name PlayerCamera
extends Camera2D

## Keeps the view inside the generated island, and on whole pixels.
##
## Joins a group rather than being wired to the world by path, so the world can
## hand it bounds without either side knowing where the other lives in the tree.
##
## ⚠️ This camera is `top_level` and does its OWN smoothing, rather than using
## Godot's position_smoothing. It has to be, to be pixel-perfect: as a normal
## child it inherits the player's fractional position, and Godot's smoothing
## then lands the view on fractional coordinates too. Measured before this
## change: the view centre was off-grid on 99.6% of frames, worst remainder
## 0.5px. With snap_2d_transforms_to_pixel on, every sprite rounds its own
## screen position independently from there, so neighbouring tiles round
## different ways on different frames — that is the shimmer along tile seams
## the phase spec calls jitter.
##
## Being top_level also means `position` is world space, so the smoothed value
## can simply be rounded before it is written.

const GROUP := "player_camera"

@export_group("Follow")
## Higher is snappier. Frame-rate independent — see the exponential below.
@export var smoothing_speed := 6.0

@export_group("Shake")
## Peak offset in pixels at full trauma.
@export var max_shake := Vector2(3.0, 2.0)
## Trauma lost per second. Higher = snappier settle.
@export var trauma_decay := 2.4

@export_group("Pixel perfect")
## Round the view onto whole pixels every frame. Exposed so the effect can be
## toggled and compared rather than taken on trust.
@export var pixel_snap := true

## While true the camera stops following the player, leaving `position` and
## `zoom` free for an AnimationPlayer to drive. Shake and pixel rounding still
## run, because a cutscene wants those as much as play does.
##
## This is the whole integration point for cinematics: set it, keyframe the
## camera, clear it. Nothing else in this file knows what an intro is, and the
## placeholder zoom animation can be replaced with a multi-shot pan without
## touching a line here.
var cinematic := false

## 0..1. Squared before use so small knocks stay gentle and only big ones bite.
var _trauma := 0.0
## The un-rounded follow position. Kept separately so rounding never feeds back
## into the smoothing and stalls it short of the target.
var _smoothed := Vector2.ZERO
var _started := false


func _ready() -> void:
	add_to_group(GROUP)
	# Runs AFTER every default-priority node in the idle frame, the child
	# AnimationPlayer included. That ordering is what lets a keyframed position
	# still come out pixel-snapped: the animation writes a fractional value,
	# and this rounds it before the frame is drawn.
	process_priority = 10
	# Godot's own smoothing is replaced, not layered on top of.
	position_smoothing_enabled = false
	top_level = true
	_smoothed = _target()
	_commit()


## An empty rect clears the limits, for a room that does not want any.
func set_world_bounds(bounds: Rect2) -> void:
	if bounds.size == Vector2.ZERO:
		limit_left = -10000000
		limit_top = -10000000
		limit_right = 10000000
		limit_bottom = 10000000
		return
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


## Drop the camera straight onto its target instead of easing in from wherever
## it happened to start. Without this the view glides across the map on load,
## because the world moves the player to its spawn tile after the scene builds.
func snap_to_target() -> void:
	_smoothed = _target()
	_commit()
	reset_smoothing()


## Called by anything that wants a kick — harvest hits, and later impacts.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## How far the view centre currently sits from a whole pixel. The regression
## asserts this is zero; it is the whole point of the file.
func pixel_error() -> Vector2:
	var centre := get_screen_center_position()
	return (centre - centre.round()).abs()


func _process(delta: float) -> void:
	_update_shake(delta)
	if cinematic:
		# An animation owns the position now. Keep it on whole pixels and keep
		# the follow position in step, so clearing the flag resumes from where
		# the camera actually is rather than snapping back.
		_smoothed = global_position
		_commit()
		return
	# Exponential rather than a plain lerp by delta: this is the same easing at
	# any frame rate, which matters because headless runs _process uncapped.
	var weight: float = 1.0 - exp(-smoothing_speed * delta)
	_smoothed = _smoothed.lerp(_target(), clampf(weight, 0.0, 1.0))
	_commit()


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	var amount := _trauma * _trauma
	# Rounded: a half-pixel shake on a pixel-art game is not a subtler shake,
	# it is the same shake plus the shimmer this file exists to remove.
	offset = (Vector2(
		randf_range(-max_shake.x, max_shake.x),
		randf_range(-max_shake.y, max_shake.y)) * amount).round()


## Writes the smoothed position out, rounded when snapping is on. The limits are
## whole numbers, so Godot clamping this afterwards cannot reintroduce a
## fraction.
func _commit() -> void:
	global_position = _smoothed.round() if pixel_snap else _smoothed


## What the camera follows: whatever it hangs under, usually the player. Read
## through the parent rather than stored, so reparenting the player between
## rooms needs no notification here.
func _target() -> Vector2:
	var parent := get_parent() as Node2D
	return parent.global_position if parent != null else global_position
