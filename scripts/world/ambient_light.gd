extends PointLight2D

## Fades a light out during the day so it never glares at midday.
##
## Drop this on any PointLight2D that represents a small in-world light; it
## keeps the authored energy as its night-time maximum.

## Fraction of the authored energy that still shows in full daylight.
@export_range(0.0, 1.0) var day_floor := 0.0

var _full_energy := 1.0


func _ready() -> void:
	_full_energy = energy
	DayNight.ticked.connect(_on_ticked)
	_on_ticked(DayNight.time_of_day)


func _on_ticked(_time_of_day: float) -> void:
	energy = _full_energy * lerpf(day_floor, 1.0, DayNight.darkness())
