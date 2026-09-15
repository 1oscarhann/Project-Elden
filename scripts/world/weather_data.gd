class_name WeatherData
extends Resource

## One kind of weather, as pure data.
##
## Adding weather is a new .tres in resources/weather/ and NOTHING else — the
## state machine picks by weight, the view reads the particle fields, and the
## warmth, thirst and fire systems read their own multiplier. No system in the
## game ever learns what "rain" is.

@export var id := ""
@export var display_name := ""

@export_group("How often, and for how long")
## Relative chance of being picked. Clear carries the biggest number on purpose
## — this is a cozy game, so most of the time the sun is out.
@export var weight := 1.0
@export var min_seconds := 90.0
@export var max_seconds := 200.0

@export_group("Look")
## MULTIPLIED into the day/night gradient rather than replacing it, so overcast
## reads as overcast at noon AND at dusk. White is no change at all.
@export var sky_tint := Color.WHITE
## Particles per second falling. 0 for weather that does not fall.
@export var particle_amount := 0
@export var particle_velocity := Vector2(-40.0, 420.0)
@export var particle_colour := Color(0.72, 0.82, 0.95, 0.55)
## Pixel size of one drop: x across, y down. Rain is a streak, not a dot.
@export var particle_size := Vector2(1.0, 7.0)
@export var particle_lifetime := 0.6
## Flat haze drawn over the world, 0..1. Fog's whole visual is this.
@export_range(0.0, 1.0) var haze := 0.0
@export var haze_colour := Color(0.80, 0.84, 0.86)

@export_group("What it does to the player")
## Multiplies the warmth DRAIN only, never the recovery — exactly like the
## hunger/thirst deprivation multiplier, and for the same reason: weather must
## never be a substitute for a fire.
@export var warmth_drain_multiplier := 1.0
## ⚠️ Below 1.0 for rain. ROADMAP_V2 line 16 is truncated mid-sentence
## ("weather will want to interact with these stats (e.g. rain") — a wet day
## making you less thirsty is the obvious completion, and it is flagged as a
## reading rather than as the doc's words.
@export var thirst_drain_multiplier := 1.0

@export_group("What it does to fire")
## Multiplies how fast a lit fire burns down. Rain is above 1.0.
@export var fire_burn_multiplier := 1.0
## Chance that a log CATCHES when relighting a dead fire. 1.0 is always.
## "Harder to light", per the spec — never impossible, because a fire you
## cannot light on a cold wet night is a game over in a game with none.
@export_range(0.05, 1.0) var light_chance := 1.0

@export_group("Sound")
## Ambience stem to cross-fade in, or "" to leave the day/night bed alone.
@export var ambience := ""


## Seconds this weather should last, rolled fresh each time it is picked.
func roll_duration(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_seconds, maxf(min_seconds, max_seconds))


func falls() -> bool:
	return particle_amount > 0


## True when being caught out in it is worse than being indoors. Drives the
## shelter mechanic, so an interior does not have to enumerate weather types.
func is_harsh() -> bool:
	return warmth_drain_multiplier > 1.0 or falls()
