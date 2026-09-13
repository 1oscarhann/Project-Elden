class_name RoomManager
extends Node2D

## Owns the player and moves them between rooms.
##
## Rooms are kept alive rather than freed: regenerating the island every time
## someone steps through a door would be slow and would undo every tree they
## chopped. Only visibility and which room holds the player ever change.
##
## Doors reach it by group call, so nothing in the world holds a reference here.

const GROUP := "rooms"
## Interiors are parked far off the island rather than stacked on top of it.
## Hiding a room does NOT disable its collision, so two rooms sharing world
## coordinates means the island's ocean still shoves the player around while
## they are stood in a hut. Keeping rooms spatially disjoint makes the inactive
## one harmless without having to walk its tree disabling shapes.
const SLOT_ORIGIN := Vector2(-20000.0, -20000.0)
const SLOT_PITCH := 2048.0

@export var fade_seconds := 0.22
## How long doors are ignored after arriving, so the door you land next to does
## not immediately send you back.
@export var door_cooldown := 0.6

@onready var _player: Node2D = $Player

var _current: Room
## Interiors are instanced on first use and then kept.
var _cache: Dictionary = {}
var _return_room: Room
var _return_position := Vector2.ZERO
var _busy := false
var _cooldown := 0.0
## A door walked into during the cooldown, held rather than dropped.
var _pending: Door
var _fade: ColorRect


func _ready() -> void:
	add_to_group(GROUP)
	_build_fade()
	var world := get_node_or_null("World") as Room
	if world == null:
		push_error("RoomManager expects a World child.")
		return
	_current = world
	_place_player(world, world.entry_position())
	world.on_entered()


func _process(delta: float) -> void:
	if _cooldown <= 0.0:
		return
	_cooldown -= delta
	if _cooldown > 0.0 or _pending == null:
		return
	var door := _pending
	_pending = null
	# Only honour it if they are genuinely still stood in the doorway, so a
	# door merely brushed past during the cooldown does not fire late.
	if is_instance_valid(door) and door.overlaps_body(_player):
		use_door(door)


## Called by any Door via group.
func use_door(door: Door) -> void:
	if _busy:
		return
	if _cooldown > 0.0:
		# Held, not dropped: walking straight onto the far door would otherwise
		# do nothing and leave the player having to step off and back on.
		_pending = door
		return
	if door.leads_inside():
		_enter(door)
	else:
		_leave(door)


func current_room() -> Room:
	return _current


func _enter(door: Door) -> void:
	var target := _room_for(door.interior_scene)
	if target == null:
		return
	_return_room = _current
	# Come back just outside the door you went in by.
	_return_position = door.global_position + door.arrival_offset
	_transition(target, target.entry_position())


func _leave(door: Door) -> void:
	if _return_room == null:
		return
	var target := _return_room
	var position := _return_position
	_return_room = null
	_transition(target, position)


func _room_for(scene: PackedScene) -> Room:
	if _cache.has(scene):
		return _cache[scene]
	var room := scene.instantiate() as Room
	if room == null:
		push_error("Door target is not a Room.")
		return null
	room.visible = false
	room.position = SLOT_ORIGIN + Vector2(0.0, SLOT_PITCH * _cache.size())
	add_child(room)
	_cache[scene] = room
	return room


func _transition(target: Room, position: Vector2) -> void:
	if target == _current:
		return
	_busy = true
	_pending = null
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, fade_seconds)
	tween.tween_callback(func(): _swap(target, position))
	tween.tween_property(_fade, "color:a", 0.0, fade_seconds)
	tween.tween_callback(func():
		_busy = false
		_cooldown = door_cooldown)


func _swap(target: Room, position: Vector2) -> void:
	if _current != null:
		_current.on_exited()
		_current.visible = false
	_current = target
	target.visible = true
	_place_player(target, position)
	target.on_entered()


## Reparent rather than keep a player per room: the player carries its camera
## and must Y-sort against whichever room's scenery it is standing in.
func _place_player(room: Room, position: Vector2) -> void:
	var layer := room.sort_layer()
	if layer == null:
		push_error("Room %s has no sort layer." % room.name)
		return
	if _player.get_parent() != layer:
		_player.reparent(layer, false)
	_player.global_position = position
	get_tree().call_group(PlayerCamera.GROUP, "set_world_bounds", room.camera_bounds())
	get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")


## Built in code so the fade needs no scene wiring and always sits on top.
func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
