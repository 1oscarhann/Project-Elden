class_name Harvestable
extends Node2D

## A tree, bush or rock the player can chop for materials.
##
## All of its behaviour comes from an exported HarvestableData, so this script
## never learns what a "tree" is. Regrowth is modelled as a stage ladder: a node
## with explicit growth_stages climbs it one rung per regrow_seconds, and a
## simple node is just the two-rung ladder [harvested, full].

signal harvested(data: HarvestableData)
signal stage_changed(stage: int)

@export var data: HarvestableData

@export_group("Feel")
## Camera trauma added per swing. Subtle — cozy, not violent.
@export_range(0.0, 1.0) var shake_per_hit := 0.22

@onready var _sprite: Sprite2D = $Sprite
@onready var _particles: CPUParticles2D = $Particles
@onready var _body: StaticBody2D = $Body
@onready var _interact: Area2D = $Interact

var _stages: Array[Texture2D] = []
var _stage := 0
var _hits := 0
var _regrow_left := 0.0
var _player_in_reach := false
var _rng := RandomNumberGenerator.new()
## Separate stream for looks, seeded by position — see _ready().
var _visual_rng := RandomNumberGenerator.new()
var _tween: Tween
## Resting scale, so the squash tween and the data scale do not fight.
var _base_scale := Vector2.ONE


func _ready() -> void:
	_rng.randomize()
	if data == null:
		push_error("Harvestable has no HarvestableData assigned.")
		set_process(false)
		return
	# Which variant this node wears is seeded from where it stands, so a given
	# island always looks the same while drops stay genuinely random.
	_visual_rng.seed = hash(Vector2i(position.round()))
	# Built element-by-element: a ternary here yields an untyped Array, which
	# will not assign to Array[Texture2D].
	_stages.clear()
	if data.is_staged():
		for texture in data.growth_stages:
			_stages.append(texture)
	else:
		_stages.append(_pick(data.harvested_variants, data.harvested_sprite))
		_stages.append(_pick(data.sprite_variants, data.sprite))
	_stage = _stages.size() - 1
	_interact.body_entered.connect(_on_reach_entered)
	_interact.body_exited.connect(_on_reach_exited)
	_particles.color = data.particle_colour
	_apply_stage()


func _process(delta: float) -> void:
	if is_ready() or _regrow_left <= 0.0:
		return
	_regrow_left -= delta
	if _regrow_left <= 0.0:
		_set_stage(_stage + 1)
		if not is_ready():
			_regrow_left = data.regrow_seconds


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_reach and is_ready() and event.is_action_pressed("interact"):
		hit()
		get_viewport().set_input_as_handled()


func is_ready() -> bool:
	return _stage >= _stages.size() - 1


## One swing. Returns true when this swing finished the node off.
func hit() -> bool:
	if not is_ready():
		return false
	# Tell the player to swing and the camera to kick, without either knowing
	# this node exists.
	get_tree().call_group("player", "swing", global_position - Vector2(0, 8))
	get_tree().call_group(PlayerCamera.GROUP, "add_trauma", shake_per_hit)
	Audio.play("chop")
	_particles.restart()
	_particles.emitting = true
	_squash()
	_hits += 1
	if _hits < data.hits_required:
		return false
	_hits = 0
	_award_drops()
	_set_stage(0)
	_regrow_left = data.regrow_seconds
	harvested.emit(data)
	return true


# --- persistence ------------------------------------------------------------

## True when this node is exactly as the generator left it, so the world can
## skip writing it to the save entirely.
func is_untouched() -> bool:
	return is_ready() and _hits == 0


func save_data() -> Dictionary:
	return {"stage": _stage, "hits": _hits, "regrow": _regrow_left}


## The argument is named `state`, not `data`: this class already has a `data`
## member holding its HarvestableData, and shadowing it here would be a trap.
func load_data(state: Dictionary) -> void:
	_hits = maxi(0, int(state.get("hits", 0)))
	_regrow_left = maxf(0.0, float(state.get("regrow", 0.0)))
	# Through _set_stage rather than the field, so the sprite, the collider and
	# the stage_changed listeners all catch up.
	_set_stage(int(state.get("stage", _stages.size() - 1)))


## One of `variants`, or `fallback` when no variants are configured.
func _pick(variants: Array[Texture2D], fallback: Texture2D) -> Texture2D:
	if variants.is_empty():
		return fallback
	return variants[_visual_rng.randi_range(0, variants.size() - 1)]


func _award_drops() -> void:
	for drop in data.drops:
		if drop == null or drop.item_id.is_empty():
			continue
		var count := drop.roll(_rng)
		if count <= 0:
			continue  # An entry whose chance did not come up.
		# Anything that will not fit is simply lost. A cozy game should not
		# refuse to let you chop a tree because your bag is full.
		Inventory.add_item(drop.item_id, count)


func _set_stage(value: int) -> void:
	_stage = clampi(value, 0, _stages.size() - 1)
	_apply_stage()
	stage_changed.emit(_stage)


func _apply_stage() -> void:
	var texture: Texture2D = _stages[_stage]
	_sprite.texture = texture
	# Re-anchor per stage: the bush sizes and the stump are different heights,
	# and the origin has to stay on the art's base for Y-sorting to hold.
	_sprite.offset = SpriteAnchor.base_offset(texture)
	_base_scale = Vector2.ONE * data.sprite_scale
	_sprite.scale = _base_scale
	# A stump or a sapling should not block the path a full tree does.
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	var solid := data.blocks_movement and is_ready()
	_body.collision_layer = 1 if solid else 0
	_interact.monitoring = true


## The satisfying bit: a quick squash-stretch that settles back.
func _squash() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_sprite.scale = _base_scale * Vector2(1.18, 0.84)
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", _base_scale, 0.32)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_reach_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_reach = true
		_sprite.modulate = Color(1.12, 1.12, 1.12)


func _on_reach_exited(body: Node2D) -> void:
	if body is Player:
		_player_in_reach = false
		_sprite.modulate = Color.WHITE

