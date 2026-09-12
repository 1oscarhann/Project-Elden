extends CanvasModulate

## Tints the whole world by time of day.
##
## The palette lives in an exported Gradient rather than lerp maths buried in
## code, so the look can be retuned by dragging colour stops. Night deliberately
## bottoms out well above black — this is a cozy game, not a horror one.

@export var gradient: Gradient


func _ready() -> void:
	DayNight.ticked.connect(_on_ticked)
	_on_ticked(DayNight.time_of_day)


func _on_ticked(time_of_day: float) -> void:
	if gradient != null:
		color = gradient.sample(time_of_day)
