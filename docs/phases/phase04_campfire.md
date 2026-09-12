# Phase 4 — Campfire & Wood-Pile Fuel Mechanic

**Goal:** the heart of the game. A campfire you feed wood into; it burns fuel over time; being
near a lit fire keeps you warm at night; if it runs out you get cold (but never die).

## Assets
- `fire_animation.png` / `fire_animation2.png` from the dungeon pack → the flame animation.
  Import at Nearest, slice into a looping `SpriteFrames` animation.

## Scene: `scenes/world/Campfire.tscn`
```
Campfire (Node2D)                 # script: scripts/world/campfire.gd
├── Flame (AnimatedSprite2D)      # fire_animation; scale/brightness by fuel
├── WarmthArea (Area2D)           # radius that marks "near the fire"
│   └── CollisionShape2D          # circle
├── Light (PointLight2D)          # warm glow, radius/energy scale with fuel
└── Interact (Area2D)             # player enters + presses key to add wood
```

## Fuel logic (`campfire.gd`)
- `fuel: float` (0..max). Burns down at `burn_rate * delta` while `fuel > 0`.
- Flame + light **scale with fuel**: low fuel = small dim flickery flame, full = big bright.
  When `fuel == 0`: flame off, light off, embers optional.
- Player can **add wood**: when in the `Interact` area and pressing the interact key, if they have
  wood in inventory (placeholder count until Phase 6), consume 1 wood → `fuel += wood_value`.
  For now, if inventory isn't built yet, use a temporary `GameState.wood` int.
- Expose `max_fuel`, `burn_rate`, `wood_value`, `warmth_radius` as `@export`.

## Warmth integration
- While the player's body overlaps `WarmthArea` **and** `fuel > 0`: pause warmth drain and/or
  actively restore warmth (delta-based). Feed this into the Phase 3 warmth system via signal or a
  method on `GameState` (e.g. `GameState.set_near_heat(true)`), not a hard node reference.
- At night, away from a lit fire → warmth drains as in Phase 3. This is the core tension.

## Juice
- Adding wood: small flame flare + a soft "whoomph" tween (scale pop) + a couple of ember
  particles. Keep it satisfying — this is the action the player repeats most.

## Definition of done
- Campfire burns fuel down over time with flame/light scaling to match.
- Standing near a lit fire at night keeps you warm; letting it die makes you cold.
- Adding wood works (from placeholder count or inventory) and feels juicy.

## Do NOT
- Make it placeable/moveable yet (that's base building, Phase 8) — one fixed campfire in the
  world is fine for now. But write `campfire.gd` so it could be instanced anywhere later.

Update ROADMAP + CLAUDE.md.
