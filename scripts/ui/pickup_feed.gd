extends Node

## Pickup feedback: a "+1 Wood" label over the player, and the item's icon
## flying from the player into the hotbar slot it landed in.
##
## The labels are parented to the PLAYER, not to a screen-space layer, so they
## travel with them: a fixed screen position would visibly slide off as you keep
## running, which is exactly when you are most likely to be picking things up.
## The flying icon is the opposite — it has to end on a piece of UI, so it lives
## on a CanvasLayer and starts from wherever the player currently is on screen.
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

@export_group("Flight to hotbar")
@export var fly_seconds := 0.42
## Size of the flying icon in pixels. The atlas cells are 32px, which is far too
## big against a 640x360 viewport.
@export var fly_icon_size := Vector2(14.0, 14.0)
## How far the icon arcs upward before it turns for the hotbar. A straight line
## reads as a UI element sliding; an arc reads as a thing being thrown.
@export var fly_arc := 26.0

## Labels currently alive, used only to work out where the next one goes.
var _live := 0
## Its own layer, above the world and below the pause menu.
var _layer: CanvasLayer


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	Inventory.item_gained.connect(_on_item_gained)


func _on_item_gained(id: String, count: int) -> void:
	var player := _player()
	if player == null:
		return
	_fly_to_hotbar(id, player)
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


## Sends the item's icon from the player to the hotbar slot it landed in.
##
## The destination is looked up AFTER the gain, so it is the slot the item
## actually went to rather than a guess. An item that did not reach the hotbar
## at all — it stacked further back in the bag — gets no flight, because there
## is nothing on screen to fly to and a icon sailing into a corner would be a
## lie about where it went.
func _fly_to_hotbar(id: String, player: Node2D) -> void:
	var icon := ItemDB.icon(id)
	var bars := get_tree().get_nodes_in_group("hotbar")
	if icon == null or bars.is_empty():
		return
	var hotbar = bars[0]
	var slot := _hotbar_slot_for(id)
	if slot < 0:
		return
	var target: Vector2 = hotbar.slot_centre(slot)
	if target == Vector2.ZERO:
		return

	# Where the player is on screen right now, which is where the item "is".
	var from: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0, -10)

	var sprite := TextureRect.new()
	sprite.texture = icon
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.size = fly_icon_size
	sprite.pivot_offset = fly_icon_size * 0.5
	sprite.position = from - fly_icon_size * 0.5
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(sprite)

	# Two chained legs rather than one straight line: up and out, then down into
	# the slot. Tweening x and y on the same curve would just be a diagonal.
	var apex := from.lerp(target, 0.45) + Vector2(0, -fly_arc)
	var tween := create_tween()
	tween.tween_property(sprite, "position", apex - fly_icon_size * 0.5, fly_seconds * 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position", target - fly_icon_size * 0.5, fly_seconds * 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sprite, "scale", Vector2(0.55, 0.55), fly_seconds * 0.55)
	tween.tween_callback(func():
		# The slot pops as the icon lands, so the two read as one event.
		hotbar.bump(slot)
		sprite.queue_free())


## The first hotbar slot holding this id, or -1 if it is not on the hotbar.
func _hotbar_slot_for(id: String) -> int:
	for i in Inventory.HOTBAR_SIZE:
		if Inventory.slot(i)["id"] == id:
			return i
	return -1


func _player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node2D if not players.is_empty() else null
