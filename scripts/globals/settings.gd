extends Node

## Player preferences: volumes, fullscreen, and how long a day lasts.
##
## Autoload. Stored separately from the save slots in user://settings.json,
## because preferences belong to the player, not to a playthrough — starting a
## new game should not reset your volume.

signal changed

const PATH := "user://settings.json"
## Anything quieter than this is treated as silence, so a slider dragged to
## zero mutes properly instead of sitting at -60 dB and still being audible.
const SILENCE_DB := -60.0

## 0..1 linear, which is what a slider hands us. Converted to dB on apply.
var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.9
var fullscreen := false
## Real seconds per in-game day. Exposed because it is the single biggest
## pacing dial in the game and everyone wants it different.
var day_length := 600.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	if FileAccess.file_exists(PATH):
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				var data: Dictionary = parsed
				master_volume = clampf(float(data.get("master_volume", master_volume)), 0.0, 1.0)
				music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
				sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 1.0)
				fullscreen = bool(data.get("fullscreen", fullscreen))
				day_length = clampf(float(data.get("day_length", day_length)), 60.0, 3600.0)
	apply()


func save_settings() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Settings: cannot write %s" % PATH)
		return
	file.store_string(JSON.stringify({
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"day_length": day_length,
	}, "\t"))
	file.close()


## Pushes every setting at the thing it controls. Safe to call repeatedly.
func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	DayNight.day_length_seconds = day_length
	# Headless has no window to resize, and asking for one prints an error.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


## Setter + apply + persist in one, so UI controls are a single line each.
func set_value(key: String, value: Variant) -> void:
	if not (key in self):
		push_error("Settings: no such setting '%s'" % key)
		return
	set(key, value)
	apply()
	save_settings()


func _set_bus(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, SILENCE_DB if linear <= 0.001 else linear_to_db(linear))
	AudioServer.set_bus_mute(index, linear <= 0.001)
