class_name PlayerCamera
extends Camera2D

## Keeps the view inside the generated island instead of panning off into void.
##
## Joins a group rather than being wired to the world by path, so the world can
## hand it bounds without either side knowing where the other lives in the tree.

const GROUP := "player_camera"

@export_group("Shake")
## Peak offset in pixels at full trauma.
@export var max_shake := Vector2(3.0, 2.0)
## Trauma lost per second. Higher = snappier settle.
@export var trauma_decay := 2.4

## 0..1. Squared before use so small knocks stay gentle and only big ones bite.
var _trauma := 0.0


func _ready() -> void:
	add_to_group(GROUP)


func set_world_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


## Drop the camera straight onto its target instead of easing in from wherever
## it happened to start. Without this the view glides across the map on load,
## because the world moves the player to its spawn tile after the scene builds.
func snap_to_target() -> void:
	reset_smoothing()


## Called by anything that wants a kick — harvest hits, and later impacts.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	var amount := _trauma * _trauma
	offset = Vector2(
		randf_range(-max_shake.x, max_shake.x),
		randf_range(-max_shake.y, max_shake.y)) * amount
