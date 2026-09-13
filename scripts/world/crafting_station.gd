class_name CraftingStation
extends Area2D

## Marks its owner as a crafting station while the player stands in range.
##
## Drop this Area2D under any world object — campfire now, workbench in Phase 8
## — and set `station_id`. It registers with the Crafting autoload the same way
## the campfire's warmth registers with GameState: by counted add/remove, so two
## overlapping stations of the same kind cannot cancel each other out.

@export var station_id := ""

## Some stations are only usable in a certain state — an unlit campfire cooks
## nothing. The owner drives this.
var active := true:
	set(value):
		if value == active:
			return
		active = value
		_refresh()

var _player_inside := false
## Whether we are currently counted in Crafting's station tally.
var _registered := false


func _ready() -> void:
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)


## Hand the registration back if this station is freed while the player is in
## it, or Crafting would keep counting a station that no longer exists.
func _exit_tree() -> void:
	if _registered:
		Crafting.remove_station(station_id)
		_registered = false


func _on_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside = true
		_refresh()


func _on_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = false
		_refresh()


## Idempotent, so it can be called as often as we like without double-counting.
func _refresh() -> void:
	var should := _player_inside and active and not station_id.is_empty()
	if should == _registered:
		return
	_registered = should
	if should:
		Crafting.add_station(station_id)
	else:
		Crafting.remove_station(station_id)
