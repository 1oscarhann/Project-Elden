extends Node2D

## The game scene's root. Owns the handful of things that belong to "a session
## is running" rather than to any one system: starting the soundtrack, fading in
## from the menu, and autosaving.
##
## Kept separate from RoomManager on purpose — the room manager's job is where
## the player is standing, and that is enough for one class.

## Slot the day-end autosave writes to. The same slot Continue reads, so
## closing the game and reopening it lands you back where you left off.
const AUTOSAVE_SLOT := 0
@export var fade_in_seconds := 0.5


func _ready() -> void:
	Audio.start_world_audio()
	# Saving on the day roll rather than on a timer means the autosave always
	# lands at a natural boundary: fresh morning, fire out or not.
	DayNight.day_passed.connect(_on_day_passed)
	_fade_in()


func _on_day_passed(_day_number: int) -> void:
	SaveManager.save_game(AUTOSAVE_SLOT)


## Black to clear, so arriving from the title screen or a load is a fade rather
## than a cut. Built in code because it is one rectangle and wiring it into the
## scene would only make the scene harder to read.
func _fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, fade_in_seconds)
	tween.tween_callback(layer.queue_free)
