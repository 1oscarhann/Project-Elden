extends CPUParticles2D

## Fireflies that drift around the player after dark.
##
## Parented under the player's camera rather than scattered across the island:
## a few dozen particles that are always where you are looking cost nothing and
## read better than thousands spread over a map you can only see 640px of.

## Particles at full night. Scaled by DayNight.darkness(), so they thin out
## through dusk and are gone by day rather than blinking off at a threshold.
@export var night_amount := 26
@export var fade_seconds := 2.0

var _target_alpha := 0.0


func _ready() -> void:
	amount = night_amount
	emitting = true
	modulate.a = 0.0


func _process(delta: float) -> void:
	# Cubed, so they hold off until it is genuinely dark instead of appearing
	# the moment the sun starts to dip.
	_target_alpha = pow(DayNight.darkness(), 3.0)
	modulate.a = move_toward(modulate.a, _target_alpha, delta / fade_seconds)
	# Stop simulating entirely once invisible — this runs every frame of every
	# day, and a daytime cost of zero is worth two lines.
	emitting = modulate.a > 0.01
