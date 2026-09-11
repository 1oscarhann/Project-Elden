class_name Battler
extends RefCounted

## Runtime combat actor. Wraps immutable BattlerData with the mutable state a
## fight needs. Nothing here is saved — GameState owns durable party state.

signal hp_changed(current: int, maximum: int)
signal died

var data: BattlerData
var is_player_side: bool = false

var hp: int = 0
var sp: int = 0
var is_defending: bool = false
## Set when this actor has already been granted a One More this round, so a
## second weakness hit doesn't chain forever.
var used_one_more: bool = false


func _init(battler_data: BattlerData, player_side: bool = false) -> void:
	data = battler_data
	is_player_side = player_side
	hp = data.max_hp
	sp = data.max_sp


func is_alive() -> bool:
	return hp > 0


func display_name() -> String:
	return data.display_name


func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, data.max_hp)
	if hp == 0:
		died.emit()


func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(data.max_hp, hp + amount)
	hp_changed.emit(hp, data.max_hp)
	return hp - before


func spend_sp(amount: int) -> bool:
	if amount > sp:
		return false
	sp = maxi(0, sp - amount)
	return true


func restore_sp(amount: int) -> int:
	var before: int = sp
	sp = mini(data.max_sp, sp + amount)
	return sp - before


## Called at the top of each round, before this side acts.
func begin_round() -> void:
	is_defending = false
	used_one_more = false


func usable_moves() -> Array[MoveData]:
	var out: Array[MoveData] = []
	for move in data.moves:
		if move != null and move.sp_cost <= sp:
			out.append(move)
	return out
