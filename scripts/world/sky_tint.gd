extends CanvasModulate

## Tints the whole world by time of day.
##
## The palette lives in an exported Gradient rather than lerp maths buried in
## code, so the look can be retuned by dragging colour stops. Night deliberately
## bottoms out well above black — this is a cozy game, not a horror one.

@export var gradient: Gradient
## How long the sky takes to turn when the weather does. Independent of
## Weather.transition_seconds on purpose — the sky can lag the particles.
@export var weather_fade := 3.0

## The weather's contribution, tweened rather than snapped. MULTIPLIED into the
## gradient sample, so overcast reads as overcast at noon AND at dusk — a
## weather colour that REPLACED the gradient would cancel the day/night cycle.
var _weather_tint := Color.WHITE
var _tween: Tween


func _ready() -> void:
	DayNight.ticked.connect(_on_ticked)
	Weather.weather_changed.connect(_on_weather_changed)
	if Weather.current != null:
		_weather_tint = Weather.current.sky_tint
	_on_ticked(DayNight.time_of_day)


func _on_ticked(time_of_day: float) -> void:
	if gradient != null:
		color = gradient.sample(time_of_day) * _weather_tint


func _on_weather_changed(data: WeatherData) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_weather_tint", data.sky_tint, weather_fade)
	# The gradient only re-samples on a clock tick, and the clock can be paused
	# (menus, tests), so drive the recolour from the tween as well.
	_tween.parallel().tween_method(
		func(_v: float): _on_ticked(DayNight.time_of_day), 0.0, 1.0, weather_fade)
