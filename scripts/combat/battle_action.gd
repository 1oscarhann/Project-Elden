class_name BattleAction
extends RefCounted

## One chosen action, handed from the UI (or the enemy AI) to BattleManager.
## Keeping this a value object means the manager never reaches into the UI.

enum Kind { ATTACK, SKILL, ITEM, DEFEND, FLEE }

var kind: Kind = Kind.ATTACK
var actor: Battler = null
var target: Battler = null
var move: MoveData = null
var item: ItemData = null


static func attack(from: Battler, to: Battler) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.ATTACK
	a.actor = from
	a.target = to
	return a


static func skill(from: Battler, to: Battler, with_move: MoveData) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.SKILL
	a.actor = from
	a.target = to
	a.move = with_move
	return a


static func use_item(from: Battler, to: Battler, with_item: ItemData) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.ITEM
	a.actor = from
	a.target = to
	a.item = with_item
	return a


static func defend(from: Battler) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.DEFEND
	a.actor = from
	a.target = from
	return a


static func flee(from: Battler) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.FLEE
	a.actor = from
	return a
