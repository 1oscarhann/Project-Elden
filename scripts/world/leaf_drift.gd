extends CPUParticles2D

## Leaves and seed fluff drifting across the view on the wind.
##
## Parented under the camera, like the fireflies, so the handful of particles
## that exist are always the ones you can see. Scattering them over a 96x96
## island would cost thousands to get the same few on screen.
##
## The wind is a slow oscillation rather than a constant, so the drift changes
## direction over a minute or so and the screen never looks like it is on rails.
## It is shared with nothing — nothing else in the game has an opinion about
## wind yet — but it is a single exported curve away from being.

## Horizontal drift in pixels per second at full gust.
@export var wind_strength := 26.0
## Seconds for one full lull-gust-lull cycle.
@export var wind_period := 38.0
## Leaves fade back after dark, when you cannot see them anyway and the
## fireflies are doing the work.
@export_range(0.0, 1.0) var night_alpha := 0.25

var _time := 0.0


func _ready() -> void:
	emitting = true
	_time = randf() * wind_period


func _process(delta: float) -> void:
	_time += delta
	# Never fully still: the baseline keeps a drift going through the lull.
	var gust: float = 0.35 + 0.65 * sin(TAU * _time / wind_period)
	gravity = Vector2(wind_strength * gust, 7.0)
	# Angle the fall with the wind so leaves look carried rather than dropped.
	direction = Vector2(gust, 0.45).normalized()
	# ⚠️ Fade, do not change `amount`. amount_ratio is a GPUParticles2D property
	# and does not exist here, and assigning `amount` on a CPUParticles2D
	# reallocates the whole system, which pops every live particle out of
	# existence. Alpha is free and continuous.
	self_modulate.a = lerpf(1.0, night_alpha, DayNight.darkness())
