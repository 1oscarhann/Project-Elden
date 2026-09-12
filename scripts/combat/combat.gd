class_name Combat
extends RefCounted

## Combat vocabulary shared by the manager, the UI and the tests.
##
## These live here rather than on BattleManager because anything that needs to
## preload the autoload script to read an enum ends up compiling that script
## before the autoload globals exist, which silently degrades the singleton to
## a bare Node. Shared constants belong in a plain class.

enum Phase { IDLE, ROUND_START, PLAYER, ENEMY, FINISHED }
enum Outcome { VICTORY, DEFEAT, FLED }

## Hitting a weakness or landing a crit grants the attacker one extra action,
## once per round. This is the Persona "One More" hook, and it's the reason the
## type chart is worth learning rather than memorising once (SPEC §6).
## Set false for plain Pokemon-style damage multipliers.
const ONE_MORE_ENABLED := true

## Chance to escape, before the speed difference nudges it.
const BASE_FLEE_CHANCE := 0.5

## How much each point of speed advantage/disadvantage shifts the flee chance.
const FLEE_SPEED_WEIGHT := 0.02
const FLEE_CHANCE_MIN := 0.05
const FLEE_CHANCE_MAX := 0.95


## The odds `actor` escapes, given the fastest opposing speed it's up against.
## Pure math only — BattleManager still decides whether a flee is even allowed
## (see its boss check) and rolls the actual chance.
static func flee_chance(actor_speed: int, fastest_opposing_speed: int) -> float:
	return clampf(
		BASE_FLEE_CHANCE + (float(actor_speed - fastest_opposing_speed) * FLEE_SPEED_WEIGHT),
		FLEE_CHANCE_MIN,
		FLEE_CHANCE_MAX
	)
