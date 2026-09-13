class_name Room
extends Node2D

## Anywhere the player can be: the island, or a building interior.
##
## The room manager needs only two things from a room — where to stand the
## player on arrival, and which node Y-sorts them against that room's scenery.
## Everything else is the room's own business.

## The Y-sorted node the player is reparented into while in this room.
func sort_layer() -> Node2D:
	return get_node_or_null("Props") as Node2D


## Where the player appears when they arrive.
func entry_position() -> Vector2:
	var marker := get_node_or_null("Entry") as Node2D
	return marker.global_position if marker != null else global_position


## Camera limits while in this room. An empty rect means "no limits".
func camera_bounds() -> Rect2:
	return Rect2()


## Hooks for rooms that care. An interior turns its shelter warmth on here.
func on_entered() -> void:
	pass


func on_exited() -> void:
	pass
