extends Node

## Player stats. Warmth today; health and hunger land in later phases.
##
## Autoload. Warmth is deliberately a *soft* stat — running out slows the player
## down and tints the screen, and that is all. There is no death in this game.

signal warmth_changed(warmth: float)
## Fires only on the transition, so listeners don't have to diff it themselves.
signal cold_changed(is_cold: bool)

const MAX_WARMTH := 100.0

@export_group("Warmth rates, per second")
## At 2.5 a fully warm player takes 40s to go cold away from a fire — enough to
## cross a stretch of island, not enough to ignore the fire.
@export var night_drain := 2.5
@export var dusk_drain := 1.5
@export var day_regen := 8.0
## Regained while inside a heat source, at any time of day.
@export var heat_regen := 20.0

@export_group("Cold penalty")
## At or below this warmth the player counts as cold.
@export_range(0.0, 100.0) var cold_threshold := 40.0
## Movement multiplier at zero warmth. Never 0 — cold is a nuisance, not a wall.
@export_range(0.1, 1.0) var min_speed_factor := 0.6

var warmth := MAX_WARMTH

## How many heat sources currently contain the player. Phase 4's campfire just
## calls add/remove on its area signals, so none of the warmth maths below ever
## needs to know what a campfire is.
var _heat_sources := 0

## Mirrors DayNight's phase. Cached from the signal rather than polled, and
## re-synced in _ready in case the clock moved before we connected.
var _phase := DayNight.Phase.DAY
var _was_cold := false


func _ready() -> void:
	_phase = DayNight.phase
	DayNight.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	var rate := warmth_rate()
	if rate != 0.0:
		set_warmth(warmth + rate * delta)


## Current warmth change per second. Being near heat always wins over the clock.
func warmth_rate() -> float:
	if is_warmed():
		return heat_regen
	match _phase:
		DayNight.Phase.NIGHT:
			return -night_drain
		DayNight.Phase.DUSK:
			return -dusk_drain
		_:
			return day_regen


func set_warmth(value: float) -> void:
	var clamped := clampf(value, 0.0, MAX_WARMTH)
	if is_equal_approx(clamped, warmth):
		return
	warmth = clamped
	warmth_changed.emit(warmth)
	var cold := is_cold()
	if cold != _was_cold:
		_was_cold = cold
		cold_changed.emit(cold)


func is_warmed() -> bool:
	return _heat_sources > 0


func is_cold() -> bool:
	return warmth <= cold_threshold


## 1.0 when comfortable, easing to min_speed_factor as warmth reaches zero.
## The player multiplies its speed by this.
func speed_factor() -> float:
	if not is_cold() or cold_threshold <= 0.0:
		return 1.0
	return lerpf(min_speed_factor, 1.0, warmth / cold_threshold)


## Coldness as 0..1 for tinting. 0 = comfortable, 1 = frozen through.
func chill() -> float:
	if not is_cold() or cold_threshold <= 0.0:
		return 0.0
	return 1.0 - warmth / cold_threshold


## Called by heat sources as the player enters and leaves their radius.
func add_heat_source() -> void:
	_heat_sources += 1


func remove_heat_source() -> void:
	_heat_sources = maxi(0, _heat_sources - 1)


func _on_phase_changed(phase: DayNight.Phase) -> void:
	_phase = phase
