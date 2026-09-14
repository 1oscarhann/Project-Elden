extends Node

## Floats a "+1 Wood" label over the player whenever something lands in the bag.
##
## The labels are parented to the PLAYER, not to a screen-space layer, so they
## travel with them: a fixed screen position would visibly slide off as you keep
## running, which is exactly when you are most likely to be picking things up.
##
## Nothing has to call this. It listens to Inventory.item_gained, which every
## drop, craft and harvest already goes through.

## How far a label rises over its life, in pixels.
@export var rise := 14.0
@export var lifetime := 0.9
## Vertical gap between labels that appear at the same moment, so a chop that
## drops wood AND fibre reads as two lines rather than one smudge.
@export var stack_gap := 9.0
@export var start_offset := Vector2(0.0, -26.0)

## Labels currently alive, used only to work out where the next one goes.
var _live := 0


func _ready() -> void:
	Inventory.item_gained.connect(_on_item_gained)


func _on_item_gained(id: String, count: int) -> void:
	var player := _player()
	if player == null:
		return
	var label := Label.new()
	label.text = "+%d %s" % [count, ItemDB.display_name(id)]
	# Not themed: this sits over the world, where the theme's dark parchment
	# text would be unreadable. Light with an outline, like the HUD labels.
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.10, 0.08))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Width is arbitrary; it exists so centring has something to centre within.
	label.size = Vector2(64.0, 10.0)
	label.pivot_offset = label.size * 0.5
	label.position = start_offset - Vector2(32.0, _live * stack_gap)
	label.z_index = 100
	player.add_child(label)

	_live += 1
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - rise, lifetime)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Held at full opacity for the first part of the life, so it is readable
	# before it starts going.
	tween.tween_property(label, "modulate:a", 0.0, lifetime * 0.45)\
		.set_delay(lifetime * 0.55)
	tween.chain().tween_callback(func():
		_live = maxi(0, _live - 1)
		label.queue_free())


func _player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node2D if not players.is_empty() else null
