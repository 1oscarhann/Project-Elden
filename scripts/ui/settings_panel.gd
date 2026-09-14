extends Control

## Volume sliders, a fullscreen toggle and a day-length dial.
##
## Reusable: both the title screen and the pause menu instance this same scene.
## Every control writes straight through Settings.set_value(), which applies and
## persists in one call, so this file holds no state of its own.

@onready var _master: HSlider = $Window/Layout/Master/Slider
@onready var _music: HSlider = $Window/Layout/Music/Slider
@onready var _sfx: HSlider = $Window/Layout/Sfx/Slider
@onready var _fullscreen: CheckButton = $Window/Layout/Fullscreen
@onready var _day_length: HSlider = $Window/Layout/DayLength/Slider
@onready var _day_label: Label = $Window/Layout/DayLength/Value


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_master.value_changed.connect(func(v): Settings.set_value("master_volume", v))
	_music.value_changed.connect(func(v): Settings.set_value("music_volume", v))
	_sfx.value_changed.connect(func(v):
		Settings.set_value("sfx_volume", v)
		# Play the click at the new level so the slider demonstrates itself.
		Audio.play("ui"))
	_fullscreen.toggled.connect(func(on): Settings.set_value("fullscreen", on))
	_day_length.value_changed.connect(func(v):
		Settings.set_value("day_length", v)
		_day_label.text = _minutes(v))
	$Window/Layout/Close.pressed.connect(close)


func open() -> void:
	# Read from Settings on every open, so a change made from the other copy of
	# this panel is reflected here.
	_master.set_value_no_signal(Settings.master_volume)
	_music.set_value_no_signal(Settings.music_volume)
	_sfx.set_value_no_signal(Settings.sfx_volume)
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_day_length.set_value_no_signal(Settings.day_length)
	_day_label.text = _minutes(Settings.day_length)
	visible = true


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _minutes(seconds: float) -> String:
	return "%d min" % roundi(seconds / 60.0)
