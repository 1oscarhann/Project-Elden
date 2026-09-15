extends CanvasLayer

## Debug HUD: day, clock, phase and warmth, plus the cold overlay.
##
## Items are NOT shown here — the hotbar and inventory panel own that. Lives on
## its own CanvasLayer so the world's day/night tint never washes out the text.

## Overlay colour applied as the player gets cold.
@export var cold_tint := Color(0.35, 0.55, 1.0)
@export_range(0.0, 1.0) var cold_tint_max_alpha := 0.35
## Applied to a stat bar once it drops to GameState.low_threshold.
const LOW_TINT := Color(1.0, 0.72, 0.55)

@onready var _clock: Label = $Frame/Readout/Clock
@onready var _warmth_label: Label = $Frame/Readout/WarmthLabel
@onready var _warmth_bar: ProgressBar = $Frame/Readout/Warmth
@onready var _hunger_label: Label = $Frame/Readout/HungerLabel
@onready var _hunger_bar: ProgressBar = $Frame/Readout/Hunger
@onready var _thirst_label: Label = $Frame/Readout/ThirstLabel
@onready var _thirst_bar: ProgressBar = $Frame/Readout/Thirst
@onready var _overlay: ColorRect = $ColdOverlay
@onready var _toast: Label = $Toast

var _toast_tween: Tween


func _ready() -> void:
	# Lifted as one by the opening cutscene. Literal rather than Intro.HUD_GROUP:
	# a global class_name resolves through a cache this script is parsed before.
	add_to_group("game_hud")
	DayNight.ticked.connect(_on_ticked)
	GameState.warmth_changed.connect(_on_warmth_changed)
	GameState.cold_changed.connect(_on_cold_changed)
	DayNight.day_passed.connect(_on_day_passed)
	GameState.hunger_changed.connect(_on_hunger_changed)
	GameState.thirst_changed.connect(_on_thirst_changed)
	_on_ticked(DayNight.time_of_day)
	_on_warmth_changed(GameState.warmth)
	_on_hunger_changed(GameState.hunger)
	_on_thirst_changed(GameState.thirst)


func _on_ticked(_time_of_day: float) -> void:
	_clock.text = "Day %d   %s   %s" % [DayNight.day, DayNight.clock_text(), DayNight.phase_name()]


func _on_warmth_changed(warmth: float) -> void:
	_warmth_bar.value = warmth
	_warmth_label.text = "Warmth %d%s" % [int(warmth), "  (by the fire)" if GameState.is_warmed() else ""]
	_overlay.color = Color(cold_tint, GameState.chill() * cold_tint_max_alpha)


## Both bars tint as they run low, the same cue the warmth bar uses when cold —
## a colour change rather than a number to read.
func _on_hunger_changed(value: float) -> void:
	_hunger_bar.value = value
	_hunger_label.text = "Hunger %d" % int(value)
	_hunger_bar.modulate = LOW_TINT if value <= GameState.low_threshold else Color.WHITE


func _on_thirst_changed(value: float) -> void:
	_thirst_bar.value = value
	_thirst_label.text = "Thirst %d" % int(value)
	_thirst_bar.modulate = LOW_TINT if value <= GameState.low_threshold else Color.WHITE


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
