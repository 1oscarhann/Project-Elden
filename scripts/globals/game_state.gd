extends Node

## Player stats. Warmth today; health and hunger land in later phases.
##
## Autoload. Warmth is deliberately a *soft* stat — running out slows the player
## down and tints the screen, and that is all. There is no death in this game.

signal warmth_changed(warmth: float)
## Fires only on the transition, so listeners don't have to diff it themselves.
signal cold_changed(is_cold: bool)
signal hunger_changed(hunger: float)
signal thirst_changed(thirst: float)

const MAX_WARMTH := 100.0
const MAX_HUNGER := 100.0
const MAX_THIRST := 100.0

@export_group("Warmth rates, per second")
## At 2.5 a fully warm player takes 40s to go cold away from a fire — enough to
## cross a stretch of island, not enough to ignore the fire.
@export var night_drain := 2.5
@export var dusk_drain := 1.5
@export var day_regen := 8.0
## Regained while inside a heat source, at any time of day.
@export var heat_regen := 20.0

@export_group("Hunger and thirst, per second")
## Both drain far more slowly than warmth: warmth is the night's pressure, these
## are the day's. At 0.55 a full belly lasts about 3 in-game days; at 0.75 a full
## flask lasts about 2.2. Slow enough to forget about for a while, not slow
## enough to ignore.
@export var hunger_drain := 0.55
@export var thirst_drain := 0.75

@export_group("Hunger and thirst penalties")
## At or below this, the stat starts to bite. Nothing happens above it.
@export_range(0.0, 100.0) var low_threshold := 20.0
## ⚠️ SOFT, and enforced to be. Running empty makes you feel the cold sooner and
## slows you a little; it never damages and never kills. At zero the penalties
## simply sit at their maximum — that is the whole design, same as warmth.
##
## Warmth drain is multiplied by up to this much when both are empty.
@export_range(1.0, 3.0) var empty_warmth_multiplier := 1.8
## Movement multiplier contributed at fully empty, per stat.
@export_range(0.5, 1.0) var empty_speed_factor := 0.85

@export_group("Cold penalty")
## At or below this warmth the player counts as cold.
@export_range(0.0, 100.0) var cold_threshold := 40.0
## Movement multiplier at zero warmth. Never 0 — cold is a nuisance, not a wall.
@export_range(0.1, 1.0) var min_speed_factor := 0.6

var warmth := MAX_WARMTH
var hunger := MAX_HUNGER
var thirst := MAX_THIRST

## True once the opening has played, so it plays ONCE per save and never again.
## Lives here rather than in the intro scene because the intro is instanced
## fresh with every scene load and would have nowhere to remember it.
var intro_shown := true

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
	set_hunger(hunger - hunger_drain * delta)
	# Weather touches thirst but not hunger: a wet day keeps you damp and less
	# parched, it does not feed you.
	set_thirst(thirst - thirst_drain * Weather.thirst_multiplier() * delta)


## Current warmth change per second. Being near heat always wins over the clock.
##
## An empty stomach or a dry throat makes the cold bite sooner — it multiplies
## the DRAIN only, never the recovery, so food and water can never substitute
## for a fire.
func warmth_rate() -> float:
	if is_warmed():
		return heat_regen
	# ⚠️ BOTH multipliers apply to the DRAIN branches only, never to day_regen.
	# Weather can make a night bite harder; it can never stand in for a fire,
	# and a sunny day must never heat you faster than a clear one.
	var bite := deprivation_multiplier() * Weather.warmth_multiplier()
	match _phase:
		DayNight.Phase.NIGHT:
			return -night_drain * bite
		DayNight.Phase.DUSK:
			return -dusk_drain * bite
		_:
			return day_regen


## 1.0 when fed and watered, rising to empty_warmth_multiplier when both are
## empty. Each stat contributes half. Weather is a SEPARATE multiplier applied
## alongside this one in warmth_rate(), not folded in here — they are different
## reasons to be cold and the HUD may want to say which.
func deprivation_multiplier() -> float:
	var extra := empty_warmth_multiplier - 1.0
	return 1.0 + extra * 0.5 * (_lack(hunger) + _lack(thirst))


## How short of the threshold a stat is, 0..1. Zero while it is comfortable.
func _lack(value: float) -> float:
	if low_threshold <= 0.0 or value >= low_threshold:
		return 0.0
	return 1.0 - value / low_threshold


## True while either stat is low enough to be applying a penalty.
func is_deprived() -> bool:
	return hunger <= low_threshold or thirst <= low_threshold


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


func set_hunger(value: float) -> void:
	var clamped := clampf(value, 0.0, MAX_HUNGER)
	if is_equal_approx(clamped, hunger):
		return
	hunger = clamped
	hunger_changed.emit(hunger)


func set_thirst(value: float) -> void:
	var clamped := clampf(value, 0.0, MAX_THIRST)
	if is_equal_approx(clamped, thirst):
		return
	thirst = clamped
	thirst_changed.emit(thirst)


func is_warmed() -> bool:
	return _heat_sources > 0


func is_cold() -> bool:
	return warmth <= cold_threshold


## 1.0 when comfortable, easing down as warmth, hunger or thirst run out.
## The player multiplies its speed by this.
##
## ⚠️ Asserted never to reach zero. Cold, hunger and thirst are all nuisances in
## this game, never walls — the combined floor is min_speed_factor times the two
## deprivation factors, which is still comfortably walkable.
func speed_factor() -> float:
	var factor := 1.0
	if is_cold() and cold_threshold > 0.0:
		factor = lerpf(min_speed_factor, 1.0, warmth / cold_threshold)
	factor *= lerpf(1.0, empty_speed_factor, _lack(hunger))
	factor *= lerpf(1.0, empty_speed_factor, _lack(thirst))
	return factor


## Coldness as 0..1 for tinting. 0 = comfortable, 1 = frozen through.
func chill() -> float:
	if not is_cold() or cold_threshold <= 0.0:
		return 0.0
	return 1.0 - warmth / cold_threshold


## Applies an item's consumable effects, reading them from its own stats.
## Returns false if the item does nothing, so the caller knows not to spend it.
## Effects live in ItemData.stats, so a new consumable is a .tres, not a change
## here — hunger is read too, ready for when a hunger stat exists.
## ⚠️ Restore amounts live in ItemData.stats, NOT in dedicated fields.
##
## The phase spec asked for `hunger_restore` / `thirst_restore` properties, but
## `stats` is a free-form dictionary built for exactly this ("so a new kind of
## item never needs a new field"), five items already carried a `hunger` value
## from Phase 7, and this function already read it. Adding parallel fields would
## duplicate a working mechanism and orphan that data. The spec's intent —
## per-item tunable restore values in data — is met either way.
func consume(item_id: String) -> bool:
	var item := ItemDB.get_item(item_id)
	if item == null:
		return false
	var warmth_gain := item.stat("warmth", 0.0)
	var hunger_gain := item.stat("hunger", 0.0)
	var thirst_gain := item.stat("thirst", 0.0)
	# Nothing to give, so the caller must not spend the item.
	if warmth_gain <= 0.0 and hunger_gain <= 0.0 and thirst_gain <= 0.0:
		return false
	if warmth_gain > 0.0:
		set_warmth(warmth + warmth_gain)
	if hunger_gain > 0.0:
		set_hunger(hunger + hunger_gain)
	if thirst_gain > 0.0:
		set_thirst(thirst + thirst_gain)
	return true


## Drinking from a freshwater source. Restores thirst only, needs no item, and
## is refused when already full so the interact key stays free for other things.
func drink(amount: float) -> bool:
	if thirst >= MAX_THIRST:
		return false
	set_thirst(thirst + amount)
	return true


## --- persistence -----------------------------------------------------------

## Everything about the player's condition that a save has to carry.
## Health and hunger are named by the Phase 10 spec but do not exist yet; when
## they do, they go here and old saves still load because get() has a default.
func save_data() -> Dictionary:
	return {"warmth": warmth, "hunger": hunger, "thirst": thirst,
		"intro_shown": intro_shown}


func load_data(data: Dictionary) -> void:
	# Straight through the setters so the HUD and the cold transition both fire,
	# rather than assigning the fields and leaving listeners stale. Each is
	# nudged off its target first, or set_* short-circuits on an equal value and
	# never emits.
	_was_cold = false
	warmth = -1.0
	set_warmth(float(data.get("warmth", MAX_WARMTH)))
	hunger = -1.0
	set_hunger(float(data.get("hunger", MAX_HUNGER)))
	thirst = -1.0
	set_thirst(float(data.get("thirst", MAX_THIRST)))
	# ⚠️ Defaults to TRUE, unlike every other field here, and that is deliberate.
	# A save written before the intro existed has no such key, and its owner has
	# self-evidently already started their game — defaulting to false would
	# replay the opening at them every time they pressed Continue. A brand new
	# game says so explicitly (see SaveManager.new_game), which is the only way
	# the flag ever comes back false.
	intro_shown = bool(data.get("intro_shown", true))


## Called by heat sources as the player enters and leaves their radius.
func add_heat_source() -> void:
	_heat_sources += 1


func remove_heat_source() -> void:
	_heat_sources = maxi(0, _heat_sources - 1)


## Read-only, so a source that forgets to hand its registration back cannot
## be papered over by something else setting the count.
func heat_source_count() -> int:
	return _heat_sources


func _on_phase_changed(phase: DayNight.Phase) -> void:
	_phase = phase
