extends Node

## The in-game clock. Owns time-of-day, the day counter and the current phase.
##
## Autoload. Nothing polls it in _process — visuals and stats connect to its
## signals instead, so the clock stays the single source of truth for time.

enum Phase { DAWN, DAY, DUSK, NIGHT }

## Fired every frame the clock advances. Carries time_of_day in 0..1.
signal ticked(time_of_day: float)
signal phase_changed(phase: Phase)
signal day_passed(day_number: int)

## Phase boundaries as fractions of a day, ascending. Night is the implicit
## remainder: it wraps past 1.0 back round to 0.0.
const DAWN_START := 0.22
const DAY_START := 0.30
const DUSK_START := 0.72
const NIGHT_START := 0.80

## Real seconds for one whole in-game day. 10 minutes is comfortable to test.
@export var day_length_seconds := 600.0
## Where a fresh game starts — mid-morning, so there's a full day before dark.
@export_range(0.0, 1.0) var start_time_of_day := 0.34
@export var paused := false

var time_of_day := 0.0
var day := 1
var phase := Phase.DAY


func _ready() -> void:
	time_of_day = start_time_of_day
	phase = phase_at(time_of_day)


func _process(delta: float) -> void:
	if paused or day_length_seconds <= 0.0:
		return
	advance(delta / day_length_seconds)


## Push the clock on by a fraction of a day. Kept separate from _process so
## tests and debug keys can step time without waiting in real time.
func advance(fraction: float) -> void:
	time_of_day += fraction
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		day_passed.emit(day)
	var next := phase_at(time_of_day)
	if next != phase:
		phase = next
		phase_changed.emit(phase)
	ticked.emit(time_of_day)


static func phase_at(t: float) -> Phase:
	if t < DAWN_START:
		return Phase.NIGHT
	if t < DAY_START:
		return Phase.DAWN
	if t < DUSK_START:
		return Phase.DAY
	if t < NIGHT_START:
		return Phase.DUSK
	return Phase.NIGHT


## 0 in full daylight, 1 at deepest night, ramping across dawn and dusk.
## Lights scale their energy by this so they do not glare at midday.
func darkness() -> float:
	if time_of_day < DAWN_START:
		return 1.0
	if time_of_day < DAY_START:
		return inverse_lerp(DAY_START, DAWN_START, time_of_day)
	if time_of_day < DUSK_START:
		return 0.0
	if time_of_day < NIGHT_START:
		return inverse_lerp(DUSK_START, NIGHT_START, time_of_day)
	return 1.0


## --- persistence -----------------------------------------------------------

func save_data() -> Dictionary:
	return {"time_of_day": time_of_day, "day": day}


## Sets the clock without emitting day_passed for every day already elapsed —
## loading day 30 should not fire 29 day-change toasts.
func load_data(data: Dictionary) -> void:
	time_of_day = clampf(float(data.get("time_of_day", start_time_of_day)), 0.0, 0.9999)
	day = maxi(1, int(data.get("day", 1)))
	var next := phase_at(time_of_day)
	if next != phase:
		phase = next
		phase_changed.emit(phase)
	ticked.emit(time_of_day)


## 24-hour readout for the debug HUD.
func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func phase_name() -> String:
	return Phase.keys()[phase]
