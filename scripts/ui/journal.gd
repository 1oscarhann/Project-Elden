extends CanvasLayer

## The survivor's journal: ONE panel holding every menu the game has.
##
## Replaces the three separate per-key windows (Tab bag, C craft, B build). They
## were three CanvasLayers that each owned a themed window, could all be open at
## once, and shared no layout. The journal is one window with a tab strip, and
## the strip is built from a list so Farming, Cooking and Fishing can add a tab
## in a later phase rather than another standalone menu.
##
## ⚠️ It holds NO game logic. Crafting and building still live where they did;
## this only changes how they are reached, and adds the ability to act on an
## item wherever it is sitting rather than only in the hotbar.

## Tabs, in bar order. `builder` names the method that fills the page, so adding
## a tab is one entry here plus that method.
const TABS := [
	{"id": "inventory", "label": "Bag", "builder": "_build_inventory"},
	{"id": "crafting", "label": "Craft", "builder": "_build_crafting"},
	{"id": "build", "label": "Build", "builder": "_build_build"},
]

@export var slot_scene: PackedScene
@export var columns := 6
@export var open_seconds := 0.16

@onready var _root: Control = $Root
@onready var _tab_bar: HBoxContainer = $Root/Window/Layout/Tabs
@onready var _pages: Control = $Root/Window/Layout/Pages
@onready var _status: Label = $Root/Window/Layout/Status

var _open := false
var _tween: Tween
var _current := "inventory"
var _tab_buttons := {}
var _page_nodes := {}
var _slots: Array[ItemSlot] = []
var _craft_rows: Array = []


func _ready() -> void:
	for tab in TABS:
		var button := Button.new()
		button.text = tab["label"]
		button.add_theme_font_size_override("font_size", 10)
		button.custom_minimum_size = Vector2(46, 0)
		button.pressed.connect(_on_tab_pressed.bind(tab["id"]))
		_tab_bar.add_child(button)
		_tab_buttons[tab["id"]] = button

		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4)
		page.visible = false
		_pages.add_child(page)
		_page_nodes[tab["id"]] = page
		call(tab["builder"], page)

	Inventory.inventory_changed.connect(_refresh)
	Crafting.stations_changed.connect(_refresh)
	Crafting.crafted.connect(func(_r): _refresh())
	_show_tab(_current)
	_root.visible = false
	_root.modulate.a = 0.0
	_root.scale = Vector2(0.94, 0.94)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_journal"):
		set_open(not _open)
		get_viewport().set_input_as_handled()
		return
	# The old keys still work, but they open the journal ON their tab rather
	# than a window of their own — muscle memory kept, one panel gained.
	for pair in [["toggle_inventory", "inventory"], ["toggle_crafting", "crafting"],
			["toggle_build", "build"]]:
		if event.is_action_pressed(pair[0]):
			if _open and _current == pair[1]:
				set_open(false)
			else:
				_show_tab(pair[1])
				set_open(true)
			get_viewport().set_input_as_handled()
			return
	if _open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func current_tab() -> String:
	return _current


func set_open(value: bool) -> void:
	if value == _open:
		return
	_open = value
	if _tween != null and _tween.is_running():
		_tween.kill()
	if _open:
		_refresh()
		_root.visible = true
	# Pivot on the centre so it grows out of the middle rather than a corner.
	_root.pivot_offset = _root.size * 0.5
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 1.0 if _open else 0.0, open_seconds)
	_tween.tween_property(_root, "scale", Vector2.ONE if _open else Vector2(0.94, 0.94),
		open_seconds).set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN)
	if not _open:
		_tween.chain().tween_callback(func(): _root.visible = false)


func _on_tab_pressed(id: String) -> void:
	Audio.play("ui")
	_show_tab(id)


func _show_tab(id: String) -> void:
	_current = id
	for tab_id in _page_nodes:
		_page_nodes[tab_id].visible = tab_id == id
		_tab_buttons[tab_id].disabled = tab_id == id
	_refresh()


# --- Bag --------------------------------------------------------------------

func _build_inventory(page: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	page.add_child(grid)
	for i in Inventory.SLOT_COUNT:
		var slot: ItemSlot = slot_scene.instantiate()
		grid.add_child(slot)
		slot.setup(i)
		slot.activated.connect(_on_slot_activated)
		_slots.append(slot)

	var hint := Label.new()
	hint.theme_type_variation = &"PanelTextDim"
	hint.add_theme_font_size_override("font_size", 8)
	hint.text = "Click an item to use it · drag to rearrange"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)


## ⚠️ THE functional gap this whole panel exists to close: an item is acted on
## WHERE IT SITS. Previously only `Inventory.selected_item_id()` could be used,
## so anything past slot 8 was unusable until it was shuffled into the hotbar.
func _on_slot_activated(index: int) -> void:
	if Inventory.is_slot_empty(index):
		return
	if Inventory.slot_is_usable(index):
		if Inventory.use_slot(index):
			Audio.play("eat")
		return
	if Inventory.slot_is_placeable(index):
		# Building needs the world, so the journal gets out of the way first.
		var id: String = Inventory.slot(index)["id"]
		set_open(false)
		get_tree().call_group("player", "begin_build", id)
		return
	Audio.play("ui")
	_flash("%s is not something you can use" % ItemDB.display_name(Inventory.slot(index)["id"]))


# --- Craft ------------------------------------------------------------------

func _build_crafting(page: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for recipe in Crafting.all_recipes():
		_craft_rows.append(_make_recipe_row(recipe, list))


func _make_recipe_row(recipe: RecipeData, list: Control) -> Dictionary:
	var row := PanelContainer.new()
	# Rows sit inside the parchment window, so they take the inset tan fill
	# rather than stacking a second sheet of parchment on the first.
	row.theme_type_variation = &"RecipeRow"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
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
	title.add_theme_font_size_override("font_size", 9)
	text.add_child(title)

	var detail := Label.new()
	detail.theme_type_variation = &"PanelTextDim"
	detail.add_theme_font_size_override("font_size", 7)
	text.add_child(detail)

	var button := Button.new()
	button.text = "Craft"
	button.add_theme_font_size_override("font_size", 8)
	button.custom_minimum_size = Vector2(40, 0)
	button.pressed.connect(func(): Crafting.craft(recipe))
	box.add_child(button)

	list.add_child(row)
	return {"recipe": recipe, "row": row, "title": title, "detail": detail, "button": button}


# --- Build ------------------------------------------------------------------

func _build_build(page: Control) -> void:
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 2)
	page.add_child(list)
	var hint := Label.new()
	hint.theme_type_variation = &"PanelTextDim"
	hint.add_theme_font_size_override("font_size", 8)
	hint.text = "Pick something to place, then click a spot in the world"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)


## Rebuilt on every refresh: what you can build changes as the bag does, and the
## list is short enough that rebuilding it is cheaper than diffing it.
func _refresh_build() -> void:
	var list: Control = _page_nodes["build"].get_node("List")
	for child in list.get_children():
		child.queue_free()
		list.remove_child(child)
	var any := false
	for id in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		if item == null or not item.is_placeable() or not Inventory.has(id, 1):
			continue
		any = true
		var row := PanelContainer.new()
		row.theme_type_variation = &"RecipeRow"
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		row.add_child(box)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = item.icon
		box.add_child(icon)
		var title := Label.new()
		title.theme_type_variation = &"PanelText"
		title.add_theme_font_size_override("font_size", 9)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text = "%s  x%d" % [item.display_name, Inventory.count(id)]
		box.add_child(title)
		var button := Button.new()
		button.text = "Place"
		button.add_theme_font_size_override("font_size", 8)
		button.custom_minimum_size = Vector2(40, 0)
		button.pressed.connect(func():
			set_open(false)
			get_tree().call_group("player", "begin_build", id))
		box.add_child(button)
		list.add_child(row)
	if any:
		return
	var empty := Label.new()
	empty.theme_type_variation = &"PanelTextDim"
	empty.add_theme_font_size_override("font_size", 8)
	empty.text = "Nothing to build yet — craft a kit first"
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(empty)


# --- shared -----------------------------------------------------------------

func _refresh() -> void:
	if not _open:
		return
	for slot in _slots:
		slot.refresh()
		slot.set_selected(slot.slot_index == Inventory.selected_hotbar)
	if _current == "crafting":
		var stations := Crafting.nearby_stations()
		_status.text = "At: %s" % ", ".join(stations) if not stations.is_empty() else "Hand crafting"
		for entry in _craft_rows:
			var recipe: RecipeData = entry["recipe"]
			var can := Crafting.can_craft(recipe)
			var suffix := " x%d" % recipe.result_count if recipe.result_count > 1 else ""
			entry["title"].text = ItemDB.display_name(recipe.result_item_id) + suffix
			entry["detail"].text = _detail_text(recipe)
			entry["button"].disabled = not can
			# Grey the whole row so an unreachable branch still reads as a branch.
			entry["row"].modulate = Color.WHITE if can else Color(1, 1, 1, 0.45)
		_sort_craft_rows()
	elif _current == "build":
		_refresh_build()
		_status.text = "Build"
	else:
		_status.text = "Bag"


## ⚠️ What you can make NOW floats to the top, then what the station you are
## stood at offers, then the rest.
##
## Found by rendering rather than by reading: walking to a cook pot and opening
## the menu showed Bone Tool, Campfire Kit, Fence and Plank — the four dishes
## the pot exists for were below the fold behind nineteen alphabetical rows.
## Nothing is hidden or removed, because a visible locked branch is how the
## player learns the tree exists; the order just stops burying the answer.
func _sort_craft_rows() -> void:
	var ranked := _craft_rows.duplicate()
	ranked.sort_custom(func(a, b):
		var ra := _craft_rank(a["recipe"])
		var rb := _craft_rank(b["recipe"])
		if ra != rb:
			return ra < rb
		# Alphabetical inside a band, so the list does not reshuffle on every
		# refresh as ingredient counts tick past a threshold.
		return ItemDB.display_name(a["recipe"].result_item_id) \
			< ItemDB.display_name(b["recipe"].result_item_id))
	for i in ranked.size():
		var row: Control = ranked[i]["row"]
		row.get_parent().move_child(row, i)


## 0 = craftable right now · 1 = needs a station you are standing at, but you
## are short of materials · 2 = everything else.
func _craft_rank(recipe: RecipeData) -> int:
	if Crafting.can_craft(recipe):
		return 0
	if recipe.needs_station() and Crafting.has_station(recipe.required_station):
		return 1
	return 2


## "2 / 4 plank · 1 / 2 stone", plus why it is blocked if a station is missing.
func _detail_text(recipe: RecipeData) -> String:
	var parts: PackedStringArray = []
	for row in Crafting.ingredient_status(recipe):
		parts.append("%d/%d %s" % [row["have"], row["need"], ItemDB.display_name(row["item_id"])])
	var text := " · ".join(parts)
	if recipe.needs_station() and not Crafting.has_station(recipe.required_station):
		text += "     (needs %s)" % recipe.required_station
	return text


func _flash(message: String) -> void:
	_status.text = message
