extends Control

## The title screen: New Game, Continue, Settings, Quit.
##
## It is the project's main scene, so this is what boots. The buttons only ever
## call SaveManager — the menu never touches the world, the clock or the bag
## itself, so "what does starting a game mean" stays in one place.

const GAME_SCENE := "res://scenes/main/Main.tscn"

@onready var _continue: Button = $Layout/Panel/Buttons/Continue
@onready var _slot_label: Label = $Layout/Panel/Buttons/SlotLine
@onready var _settings: Control = $SettingsPanel


func _ready() -> void:
	$Layout/Panel/Buttons/NewGame.pressed.connect(_on_new_game)
	_continue.pressed.connect(_on_continue)
	$Layout/Panel/Buttons/Settings.pressed.connect(func(): _settings.open())
	$Layout/Panel/Buttons/Quit.pressed.connect(func(): get_tree().quit())
	for button in _all_buttons():
		button.pressed.connect(func(): Audio.play("ui"))
	_refresh_slot()
	# The menu is deliberately quiet — the theme starts with the world, so the
	# first thing you hear is the island.
	Audio.stop_world_audio()


## The menu only ever uses slot 0. Multiple slots exist in SaveManager and the
## pause menu can reach them; the title screen keeps the promise simple.
func _refresh_slot() -> void:
	var exists := SaveManager.has_save(0)
	_continue.disabled = not exists
	_slot_label.text = SaveManager.slot_summary(0) if exists else "No save yet"


func _on_new_game() -> void:
	SaveManager.new_game()


func _on_continue() -> void:
	if SaveManager.has_save(0):
		SaveManager.load_game(0)


func _all_buttons() -> Array:
	var out: Array = []
	for node in $Layout/Panel/Buttons.get_children():
		if node is Button:
			out.append(node)
	return out
