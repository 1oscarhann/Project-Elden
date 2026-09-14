extends CanvasLayer

## Debug HUD: day, clock, phase and warmth, plus the cold overlay.
##
## Items are NOT shown here — the hotbar and inventory panel own that. Lives on
## its own CanvasLayer so the world's day/night tint never washes out the text.

## Overlay colour applied as the player gets cold.
@export var cold_tint := Color(0.35, 0.55, 1.0)
@export_range(0.0, 1.0) var cold_tint_max_alpha := 0.35

@onready var _clock: Label = $Frame/Readout/Clock
@onready var _warmth_label: Label = $Frame/Readout/WarmthLabel
@onready var _warmth_bar: ProgressBar = $Frame/Readout/Warmth
@onready var _overlay: ColorRect = $ColdOverlay
@onready var _toast: Label = $Toast

var _toast_tween: Tween


func _ready() -> void:
	DayNight.ticked.connect(_on_ticked)
	GameState.warmth_changed.connect(_on_warmth_changed)
	GameState.cold_changed.connect(_on_cold_changed)
	DayNight.day_passed.connect(_on_day_passed)
	_on_ticked(DayNight.time_of_day)
	_on_warmth_changed(GameState.warmth)


func _on_ticked(_time_of_day: float) -> void:
	_clock.text = "Day %d   %s   %s" % [DayNight.day, DayNight.clock_text(), DayNight.phase_name()]


func _on_warmth_changed(warmth: float) -> void:
	_warmth_bar.value = warmth
	_warmth_label.text = "Warmth %d%s" % [int(warmth), "  (by the fire)" if GameState.is_warmed() else ""]
	_overlay.color = Color(cold_tint, GameState.chill() * cold_tint_max_alpha)


func _on_cold_changed(is_cold: bool) -> void:
	_warmth_bar.modulate = Color(0.6, 0.8, 1.0) if is_cold else Color.WHITE


## "Day 3" drifting up and fading, the one piece of ceremony in the game.
## Deliberately not a panel: it sits over the world for two seconds and then
## leaves, so a frame around it would be more furniture than information.
func _on_day_passed(day_number: int) -> void:
	_toast.text = "Day %d" % day_number
	if _toast_tween != null and _toast_tween.is_running():
		_toast_tween.kill()
	# Reset the drift each time, or the second toast starts where the first
	# one finished and floats off the top of the screen.
	_toast.position.y = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.5)
	_toast_tween.tween_interval(1.4)
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)
	_toast_tween.tween_property(_toast, "position:y", -10.0, 0.8)
