extends CanvasLayer

## Esc while playing: Resume, Save, Load, Settings, Quit to title.
##
## ⚠️ This node must be the FIRST child of Main, not the last. _unhandled_input
## is delivered in reverse tree order, so the last child hears Esc first — and
## Esc is already how you close the bag, the craft menu and build mode. Sitting
## first in the tree means the pause menu only ever sees an Esc that nothing
## else wanted. `layer` keeps it drawn on top regardless of tree position.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const SLOT := 0

@onready var _root: Control = $Root
@onready var _status: Label = $Root/Window/Layout/Status
@onready var _settings: Control = $SettingsPanel

var _open := false


func _ready() -> void:
	# The whole point of a pause menu is to keep working while the tree is
	# stopped, so it opts out of the pause it causes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Root/Window/Layout/Resume.pressed.connect(func(): set_open(false))
	$Root/Window/Layout/Save.pressed.connect(_on_save)
	$Root/Window/Layout/Load.pressed.connect(_on_load)
	$Root/Window/Layout/Settings.pressed.connect(func(): _settings.open())
	$Root/Window/Layout/Quit.pressed.connect(_on_quit)
	for node in $Root/Window/Layout.get_children():
		if node is Button:
			node.pressed.connect(func(): Audio.play("ui"))
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_open(not _open)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func set_open(value: bool) -> void:
	if value == _open:
		return
	_open = value
	_root.visible = _open
	# This menu DOES pause, unlike the bag: it offers to throw the session away,
	# and doing that while a deer wanders past is worse than a moment's stop.
	get_tree().paused = _open
	if _open:
		_status.text = "Slot 1 — %s" % SaveManager.slot_summary(SLOT)
		$Root/Window/Layout/Resume.grab_focus()


func _on_save() -> void:
	_status.text = "Saved." if SaveManager.save_game(SLOT) else "Could not save."


func _on_load() -> void:
	if not SaveManager.has_save(SLOT):
		_status.text = "Nothing saved yet."
		return
	# Unpause first: change_scene_to_file runs at the end of the frame, and a
	# paused tree would arrive in the new scene still stopped.
	get_tree().paused = false
	_open = false
	_root.visible = false
	SaveManager.load_game(SLOT)


func _on_quit() -> void:
	get_tree().paused = false
	_open = false
	_root.visible = false
	Audio.stop_world_audio()
	get_tree().change_scene_to_file(MENU_SCENE)
