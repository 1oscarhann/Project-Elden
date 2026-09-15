extends Node

## The weather state machine.
##
## Autoload. Picks a WeatherData at weighted random, runs it for its own rolled
## duration, then picks again. Deliberately NOT tied to any season — seasons are
## cut (ROADMAP_V2 item A), so this is a plain weighted timer, biased hard
## toward clear because a cozy game should mostly be sunny.
##
## It knows nothing about particles, warmth or fire. It owns "what is the
## weather" and emits a signal; the view, GameState and the campfire each read
## the multiplier they care about off the current WeatherData. Adding a weather
## is a .tres in resources/weather/ and no code at all.

signal weather_changed(data: WeatherData)
## Fires once per frame with the 0..1 blend, so the view can fade rather than
## cut. Separate from weather_changed because the data flips instantly and the
## look does not.
signal blend_changed(amount: float)
## Emitted when the player walks under cover and out again. Counted, so two
## overlapping shelters cannot cancel each other out.
signal shelter_changed(sheltered: bool)

const WEATHER_DIR := "res://resources/weather/"
## Weather we start on, so a new game never opens in a downpour.
const FIRST_ID := "clear"

## How long the look takes to cross over when the weather turns. The DATA
## changes instantly (so the fire starts hissing at once); only the visuals ease.
@export var transition_seconds := 4.0
## Stops the clock, for tests and screenshots.
@export var paused := false

var current: WeatherData
## Seconds remaining on the current weather.
var time_left := 0.0
## 0..1, how far the visuals have caught up with `current`.
var blend := 1.0

var _all: Array[WeatherData] = []
var _by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## How many shelters contain the player. Same counted shape as GameState's heat
## sources and Crafting's stations — proven, and impossible to double-release.
var _shelters := 0


func _ready() -> void:
	_rng.randomize()
	reload()
	var first: WeatherData = _by_id.get(FIRST_ID, _all[0] if not _all.is_empty() else null)
	if first != null:
		_apply(first, true)


func reload() -> void:
	_all.clear()
	_by_id.clear()
	var dir := DirAccess.open(WEATHER_DIR)
	if dir == null:
		push_error("Weather: cannot open %s" % WEATHER_DIR)
		return
	for file in dir.get_files():
		# Exported builds rewrite .tres to .tres.remap, same as ItemDB.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var data := load(WEATHER_DIR + name) as WeatherData
		if data == null:
			continue
		if data.id.is_empty():
			push_error("Weather: %s has no id" % name)
			continue
		if _by_id.has(data.id):
			push_error("Weather: duplicate id '%s' in %s" % [data.id, name])
			continue
		_by_id[data.id] = data
		_all.append(data)


func _process(delta: float) -> void:
	if blend < 1.0 and transition_seconds > 0.0:
		blend = minf(blend + delta / transition_seconds, 1.0)
		blend_changed.emit(blend)
	if paused or current == null:
		return
	time_left -= delta
	if time_left <= 0.0:
		_apply(_pick(), false)


# --- what everything else asks --------------------------------------------

## ⚠️ Multiplies the warmth DRAIN only. GameState applies it to the drain
## branches and never to the recovery, so weather can make a night bite harder
## but can never replace a campfire.
func warmth_multiplier() -> float:
	if current == null or is_sheltered():
		return 1.0
	return current.warmth_drain_multiplier


## Rain makes you less thirsty. Shelter does NOT cancel this: standing in a
## doorway watching it pour is still a damp day.
func thirst_multiplier() -> float:
	return 1.0 if current == null else current.thirst_drain_multiplier


## How much faster a lit fire burns down. A sheltered fire is unaffected — which
## is what makes putting one inside a hut worth doing.
func fire_burn_multiplier() -> float:
	if current == null or is_sheltered():
		return 1.0
	return current.fire_burn_multiplier


## Rolled when a log is put on a DEAD fire. Never returns false in fair weather,
## and never permanently blocks: the log is not spent on a failed light.
func log_catches() -> bool:
	if current == null or is_sheltered():
		return true
	return _rng.randf() <= current.light_chance


func is_wet() -> bool:
	return current != null and current.falls() and not is_sheltered()


func id() -> String:
	return "" if current == null else current.id


func display_name() -> String:
	return "" if current == null else current.display_name


func all_weather() -> Array[WeatherData]:
	return _all.duplicate()


func get_weather(weather_id: String) -> WeatherData:
	return _by_id.get(weather_id, null)


# --- shelter ----------------------------------------------------------------

## Called by anything the player can stand under. Counted registration, so an
## interior inside an interior still resolves correctly and a freed room that
## hands its registration back cannot take someone else's with it.
func add_shelter() -> void:
	_shelters += 1
	if _shelters == 1:
		shelter_changed.emit(true)


func remove_shelter() -> void:
	if _shelters <= 0:
		return
	_shelters -= 1
	if _shelters == 0:
		shelter_changed.emit(false)


func is_sheltered() -> bool:
	return _shelters > 0


func shelter_count() -> int:
	return _shelters


# --- driving it -------------------------------------------------------------

## Force a weather by id. For the debug key, the screenshot tool and the tests —
## normal play only ever goes through _pick().
func set_weather(weather_id: String, instant := false) -> bool:
	var data: WeatherData = _by_id.get(weather_id, null)
	if data == null:
		return false
	_apply(data, instant)
	return true


## Weighted random over every loaded WeatherData, never picking what is already
## running — otherwise "the weather changed" would sometimes visibly change
## nothing, which reads as a bug rather than as weather.
func _pick() -> WeatherData:
	var pool: Array[WeatherData] = []
	var total := 0.0
	for data in _all:
		if data == current or data.weight <= 0.0:
			continue
		pool.append(data)
		total += data.weight
	if pool.is_empty():
		return current
	var roll := _rng.randf() * total
	for data in pool:
		roll -= data.weight
		if roll <= 0.0:
			return data
	return pool[-1]


func _apply(data: WeatherData, instant: bool) -> void:
	if data == null:
		return
	var changed := data != current
	current = data
	time_left = data.roll_duration(_rng)
	if not changed and not instant:
		return
	blend = 1.0 if instant else 0.0
	weather_changed.emit(current)
	blend_changed.emit(blend)


# --- persistence ------------------------------------------------------------

func save_data() -> Dictionary:
	return {"id": id(), "time_left": time_left}


func load_data(data: Dictionary) -> void:
	# ⚠️ Shelter is NOT saved. It is a live count of areas the player is stood
	# in, and loading restarts the scene — the interiors that incremented it no
	# longer exist, so restoring the number would strand a permanent shelter.
	_shelters = 0
	var saved_id := String(data.get("id", FIRST_ID))
	var restored: WeatherData = _by_id.get(saved_id, _by_id.get(FIRST_ID, null))
	if restored == null:
		return
	_apply(restored, true)
	# A file written before weather existed has no time_left; the fresh roll
	# from _apply stands in that case rather than starting at zero.
	if data.has("time_left"):
		time_left = maxf(float(data["time_left"]), 1.0)
