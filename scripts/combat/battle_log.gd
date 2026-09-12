class_name BattleLog
extends RefCounted

## Turns a resolved action into the line of text the player reads
## (BattleUI.append_log). Pulled out of BattleManager (SPEC §6) so the state
## machine isn't also in the business of phrasing sentences.


## Describes a resolved Attack or Skill: who used what, on whom, for how much,
## with a tag for a crit, a weakness hit, a resist, or immunity.
static func describe_attack(action: BattleAction, target: Battler, result: Damage.Result) -> String:
	var verb: String = action.move.display_name if action.move != null else "Attack"
	if result.was_immune:
		return "%s uses %s. %s is unaffected." % [
			action.actor.display_name(), verb, target.display_name(),
		]

	var line: String = "%s uses %s. %s takes %d damage" % [
		action.actor.display_name(), verb, target.display_name(), result.amount,
	]
	if result.was_crit:
		line += " (CRITICAL)"
	elif result.hit_weakness:
		line += " (WEAK!)"
	elif result.was_resisted:
		line += " (resisted)"
	return line + "."


## Describes a resolved Item action. `amount` is the HP or SP actually
## recovered (already clamped to max by Battler.heal / Battler.restore_sp) —
## the caller resolves the effect first so this stays a pure formatter.
static func describe_item(action: BattleAction, item: ItemData, target: Battler, amount: int) -> String:
	match item.effect:
		ItemData.Effect.HEAL_HP:
			return "%s uses %s. %s recovers %d HP." % [
				action.actor.display_name(), item.display_name, target.display_name(), amount,
			]
		ItemData.Effect.HEAL_SP:
			return "%s uses %s. %s recovers %d SP." % [
				action.actor.display_name(), item.display_name, target.display_name(), amount,
			]
		_:
			return "%s uses %s." % [action.actor.display_name(), item.display_name]
