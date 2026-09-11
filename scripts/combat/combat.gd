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
