class_name EncounterZone
extends Area3D

## Random-encounter field (SPEC §9 step 2). While the player is inside, the
## distance they walk is banked; crossing a randomised threshold fires an
## encounter.
##
## Distance-based rather than timer-based so standing still is safe and the
## rate feels the same regardless of framerate.

signal encounter_triggered(foes: Array)

@export var table: EncounterTable
## Grace distance at zone entry (and after every fight) so you're never jumped
## the instant a battle ends.
@export var grace_metres: float = 6.0

var _banked: float = 0.0
var _threshold: float = 0.0
var _rng := RandomNumberGenerator.new()
var _armed: bool = false


func _ready() -> void:
	_rng.randomize()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_roll_threshold()


## Starts banking distance, with a grace period before the first roll.
## Called when the player enters the zone.
func arm() -> void:
	_armed = true
	_banked = -grace_metres
	_roll_threshold()


## Stops banking distance. Called when the player leaves the zone.
func disarm() -> void:
	_armed = false


## Banks `metres` of walking and, once the rolled threshold is crossed,
## emits encounter_triggered and re-arms with a fresh grace period and
## threshold. A no-op while disarmed or with no table assigned.
func accumulate(metres: float) -> void:
	if not _armed or table == null:
		return
	_banked += metres
	if _banked < _threshold:
		return

	var foe: EnemyData = table.pick(_rng)
	_banked = -grace_metres
	_roll_threshold()
	if foe != null:
		encounter_triggered.emit([foe] as Array)


func _roll_threshold() -> void:
	var base: float = float(table.steps_per_encounter) if table != null else 22.0
	# +/- 40% so the rhythm isn't metronomic.
	_threshold = base * _rng.randf_range(0.6, 1.4)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		arm()


func _on_body_exited(body: Node3D) -> void:
	if body is PlayerController:
		disarm()
