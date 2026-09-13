class_name Campfire
extends Node2D

## A campfire that burns fuel down over time and keeps the player warm.
##
## Self-contained and instanceable anywhere — it never reaches for the player or
## the world. Warmth is handed to GameState through add/remove_heat_source(),
## which is all the warmth system knows about fires.

signal fuel_changed(fuel: float, max_fuel: float)
signal lit_changed(lit: bool)

## Fuel fraction -> flame animation, largest first. Data rather than an if-chain,
## so restaging the fire means editing this list.
const STAGES: Array = [[0.60, "high"], [0.30, "medium"], [0.10, "low"], [0.0, "ember"]]

@export_group("Fuel")
@export var max_fuel := 100.0
## Fuel burnt per second while lit. At 0.5 a full fire lasts 200s against a
## 252s night, so one mid-night top-up is needed — about 5 logs a night. See
## CLAUDE.md for the arithmetic before changing this.
@export var burn_rate := 0.5
## Fuel gained per log added.
@export var wood_value := 25.0
@export var start_fuel := 40.0

@export_group("Presence")
## Radius in pixels within which the player counts as warm.
@export var warmth_radius := 56.0

@export_group("Juice")
## Scale multiplier at the peak of the "fed it a log" pop.
@export var flare_scale := 1.35
@export var flare_seconds := 0.45
## Colour of the cold coals left when the fire goes out.
@export var ember_tint := Color(0.5, 0.31, 0.26, 0.8)

@onready var _flame: AnimatedSprite2D = $Flame
@onready var _light: PointLight2D = $Light
@onready var _embers: CPUParticles2D = $Embers
@onready var _prompt: Label = $Prompt
@onready var _warmth_shape: CollisionShape2D = $WarmthArea/CollisionShape2D

var fuel := 0.0
## Multiplier tweened by the flare; kept separate so the per-frame size update
## and the tween never fight over scale.
var _flare := 1.0
var _player_in_warmth := false
var _player_in_reach := false
## Whether we are currently counted in GameState's heat sources.
var _heat_applied := false
var _stage := ""


func _ready() -> void:
	fuel = clampf(start_fuel, 0.0, max_fuel)
	(_warmth_shape.shape as CircleShape2D).radius = warmth_radius
	$WarmthArea.body_entered.connect(_on_warmth_entered)
	$WarmthArea.body_exited.connect(_on_warmth_exited)
	$Interact.body_entered.connect(_on_reach_entered)
	$Interact.body_exited.connect(_on_reach_exited)
	GameState.wood_changed.connect(_on_wood_changed)
	_refresh()


## Give back the heat source if this fire is removed while the player stands in
## it, otherwise GameState would count a fire that no longer exists.
func _exit_tree() -> void:
	if _heat_applied:
		GameState.remove_heat_source()
		_heat_applied = false


func _process(delta: float) -> void:
	if fuel > 0.0:
		set_fuel(fuel - burn_rate * delta)
	_update_visuals()
	if _player_in_reach:
		_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_reach and event.is_action_pressed("interact"):
		add_wood()
		get_viewport().set_input_as_handled()


func is_lit() -> bool:
	return fuel > 0.0


func fuel_ratio() -> float:
	return 0.0 if max_fuel <= 0.0 else clampf(fuel / max_fuel, 0.0, 1.0)


## Spend one log from the stockpile to stoke the fire. Returns false when there
## is no wood or the fire is already full.
func add_wood() -> bool:
	if fuel >= max_fuel or not GameState.spend_wood(1):
		return false
	var was_lit := is_lit()
	set_fuel(fuel + wood_value)
	_flare_up()
	if not was_lit:
		_update_visuals()
	return true


func set_fuel(value: float) -> void:
	var clamped := clampf(value, 0.0, max_fuel)
	if is_equal_approx(clamped, fuel):
		return
	var was_lit := is_lit()
	fuel = clamped
	fuel_changed.emit(fuel, max_fuel)
	if is_lit() != was_lit:
		lit_changed.emit(is_lit())
		_refresh()


## The player is warm only while standing in the radius of a *lit* fire, so both
## the area and the flame going out have to re-evaluate it. Idempotent, so it can
## be called as often as we like without double-counting.
func _refresh() -> void:
	var should_warm := _player_in_warmth and is_lit()
	if should_warm == _heat_applied:
		return
	_heat_applied = should_warm
	if should_warm:
		GameState.add_heat_source()
	else:
		GameState.remove_heat_source()


func _update_visuals() -> void:
	var ratio := fuel_ratio()
	_flame.visible = true
	_light.enabled = true
	if not is_lit():
		_show_embers()
		return
	_flame.modulate = Color.WHITE
	var stage := _stage_for(ratio)
	if stage != _stage:
		_stage = stage
		_flame.play(stage)
	# Size and light both track fuel, so a dying fire visibly shrinks.
	_flame.scale = Vector2.ONE * (lerpf(0.72, 1.05, ratio) * _flare)
	_light.energy = lerpf(0.35, 1.25, ratio) * _flare
	_light.texture_scale = lerpf(0.45, 1.0, ratio)


## A dead fire still leaves cold coals. Without this the pit vanishes entirely
## at night and the player cannot find the thing they need to relight.
func _show_embers() -> void:
	if _stage != "ember":
		_stage = "ember"
		_flame.play("ember")
	_flame.modulate = ember_tint
	_flame.scale = Vector2.ONE * 0.5
	_light.energy = 0.1
	_light.texture_scale = 0.25


static func _stage_for(ratio: float) -> String:
	for stage in STAGES:
		if ratio >= float(stage[0]):
			return String(stage[1])
	return String(STAGES[-1][1])


## The "whoomph" when a log goes on: a quick scale pop plus an ember burst.
func _flare_up() -> void:
	_embers.restart()
	_embers.emitting = true
	var tween := create_tween()
	tween.tween_property(self, "_flare", flare_scale, flare_seconds * 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_flare", 1.0, flare_seconds * 0.75)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _update_prompt() -> void:
	var wood: int = GameState.wood
	if fuel >= max_fuel:
		_prompt.text = "Fire is roaring  (%d%%)" % roundi(fuel_ratio() * 100.0)
	elif wood > 0:
		_prompt.text = "[E] add wood  x%d   ·   fire %d%%" % [wood, roundi(fuel_ratio() * 100.0)]
	else:
		_prompt.text = "no wood   ·   fire %d%%" % roundi(fuel_ratio() * 100.0)


func _on_warmth_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_warmth = true
		_refresh()


func _on_warmth_exited(body: Node2D) -> void:
	if body is Player:
		_player_in_warmth = false
		_refresh()


func _on_reach_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_reach = true
		_prompt.visible = true
		_update_prompt()


func _on_reach_exited(body: Node2D) -> void:
	if body is Player:
		_player_in_reach = false
		_prompt.visible = false


func _on_wood_changed(_count: int) -> void:
	if _player_in_reach:
		_update_prompt()
