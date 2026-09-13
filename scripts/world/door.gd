class_name Door
extends Area2D

## Walk into it to change room.
##
## A door carrying an `interior_scene` leads inward; one without it leads back
## out to wherever the player came from. It tells the room manager by group
## call, so a door never holds a reference to the manager or to the player.

## Interior to enter. Leave empty for a door that returns outside.
@export var interior_scene: PackedScene
## Where the player stands on the far side, relative to the door they arrive at.
@export var arrival_offset := Vector2(0, 16)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func leads_inside() -> bool:
	return interior_scene != null


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	# Deferred on purpose: this fires mid physics-flush, and swapping rooms
	# instances an interior whose own doors are Area2Ds. Touching area state
	# during a flush is refused by the physics server, and the freshly added
	# door comes out with its shape in a broken state — so the exit you just
	# walked in by would never fire again.
	get_tree().call_group_flags(SceneTree.GROUP_CALL_DEFERRED,
		RoomManager.GROUP, "use_door", self)
