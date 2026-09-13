extends CanvasLayer

## The crafting list. Toggled with `toggle_crafting` (C).
##
## Shows EVERY unlocked recipe, not just the ones currently craftable — a
## greyed-out row that says "needs a workbench" is how the player learns the
## tree exists. Rows are built from whatever Crafting loaded, so a new recipe
## .tres appears here with no change to this file.

@export var open_seconds := 0.16

@onready var _root: Control = $Root
@onready var _list: VBoxContainer = $Root/Window/Layout/Scroll/List
@onready var _where: Label = $Root/Window/Layout/Where

var _rows: Array = []
var _open := false
var _tween: Tween


func _ready() -> void:
	_build_rows()
	Inventory.inventory_changed.connect(_refresh)
	Crafting.stations_changed.connect(_refresh)
	Crafting.crafted.connect(func(_r): _refresh())
	_root.visible = false
	_root.modulate.a = 0.0
	_root.scale = Vector2(0.94, 0.94)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crafting"):
		set_open(not _open)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func set_open(value: bool) -> void:
	if value == _open:
		return
	_open = value
	if _tween != null and _tween.is_running():
		_tween.kill()
	if _open:
		_refresh()
		_root.visible = true
	_root.pivot_offset = _root.size * 0.5
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 1.0 if _open else 0.0, open_seconds)
	_tween.tween_property(_root, "scale", Vector2.ONE if _open else Vector2(0.94, 0.94), open_seconds)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN)
	if not _open:
		_tween.chain().tween_callback(func(): _root.visible = false)


## One row per recipe, built once. Only their labels change afterwards.
func _build_rows() -> void:
	for recipe in Crafting.all_recipes():
		var row := PanelContainer.new()
		# Rows sit inside the parchment window, so they take the inset tan fill
		# rather than stacking a second sheet of parchment on the first.
		row.theme_type_variation = &"RecipeRow"
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		row.add_child(box)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = ItemDB.icon(recipe.result_item_id)
		box.add_child(icon)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		box.add_child(text)

		var title := Label.new()
		title.theme_type_variation = &"PanelText"
		title.add_theme_font_size_override("font_size", 10)
		text.add_child(title)

		var detail := Label.new()
		detail.theme_type_variation = &"PanelTextDim"
		detail.add_theme_font_size_override("font_size", 8)
		text.add_child(detail)

		var button := Button.new()
		button.text = "Craft"
		button.add_theme_font_size_override("font_size", 9)
		button.custom_minimum_size = Vector2(44, 0)
		button.pressed.connect(func(): Crafting.craft(recipe))
		box.add_child(button)

		_list.add_child(row)
		_rows.append({"recipe": recipe, "row": row, "title": title, "detail": detail, "button": button})


func _refresh() -> void:
	if not _open:
		return
	var stations := Crafting.nearby_stations()
	_where.text = "At: %s" % ", ".join(stations) if not stations.is_empty() else "Hand crafting"
	for entry in _rows:
		var recipe: RecipeData = entry["recipe"]
		var can := Crafting.can_craft(recipe)
		var suffix := " x%d" % recipe.result_count if recipe.result_count > 1 else ""
		entry["title"].text = ItemDB.display_name(recipe.result_item_id) + suffix
		entry["detail"].text = _detail_text(recipe)
		entry["button"].disabled = not can
		# Grey the whole row so an unreachable branch still reads as a branch.
		entry["row"].modulate = Color.WHITE if can else Color(1, 1, 1, 0.45)


## "2 / 4 plank · 1 / 2 stone", plus why it is blocked if a station is missing.
func _detail_text(recipe: RecipeData) -> String:
	var parts: PackedStringArray = []
	for row in Crafting.ingredient_status(recipe):
		parts.append("%d/%d %s" % [row["have"], row["need"], ItemDB.display_name(row["item_id"])])
	var text := " · ".join(parts)
	if recipe.needs_station() and not Crafting.has_station(recipe.required_station):
		text += "     (needs %s)" % recipe.required_station
	return text
