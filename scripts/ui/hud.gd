extends CanvasLayer

## Debug HUD: day, clock, phase and warmth, plus the cold overlay.
##
## Items are NOT shown here — the hotbar and inventory panel own that. Lives on
## its own CanvasLayer so the world's day/night tint never washes out the text.

## Overlay colour applied as the player gets cold.
@export var cold_tint := Color(0.35, 0.55, 1.0)
@export_range(0.0, 1.0) var cold_tint_max_alpha := 0.35

@onready var _clock: Label = $Readout/Clock
@onready var _warmth_label: Label = $Readout/WarmthLabel
@onready var _warmth_bar: ProgressBar = $Readout/Warmth
@onready var _overlay: ColorRect = $ColdOverlay


func _ready() -> void:
	DayNight.ticked.connect(_on_ticked)
	GameState.warmth_changed.connect(_on_warmth_changed)
	GameState.cold_changed.connect(_on_cold_changed)
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
