class_name PlayerCamera
extends Camera2D

## Keeps the view inside the generated island instead of panning off into void.
##
## Joins a group rather than being wired to the world by path, so the world can
## hand it bounds without either side knowing where the other lives in the tree.

const GROUP := "player_camera"


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
