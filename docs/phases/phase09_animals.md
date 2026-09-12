# Phase 9 — Passive Animals & Hunting

**Goal:** wildlife that wanders and flees, huntable for food. Cozy, not a combat system.

## Assets
- `res://assets/animals/` — start with **Hare** and **Deer** (skittish). Each has Idle/Walk/Run/
  Hurt/Death strips (+ shadows). Build a `SpriteFrames` per animal (verify frame counts in the
  SpriteFrames editor — they vary by animal).

## Scene: `scenes/entities/Animal.tscn` (data-driven)
- `scripts/entities/animal_data.gd` → `class_name AnimalData`: `id`, `sprite_frames`, `move_speed`,
  `flee_speed`, `detection_radius`, `drops` (item drops on death, e.g. raw_meat/hide), `wander_range`.
- `Animal (CharacterBody2D)` with:
  - `AnimatedSprite2D`, `Shadow`, feet `CollisionShape2D`
  - `DetectionArea (Area2D)` sized to `detection_radius`
  - `NavigationAgent2D` for movement (bake a NavigationRegion2D on the island walkable area)
- **State machine**: IDLE → WANDER (pick random nearby point, walk) → FLEE (player entered
  detection: run directly away, faster) → back to WANDER when safe. HURT/DEATH on being hit.

## Hunting
- Interact/hit an animal (reuse the harvest input + a hit): apply damage; on death play Death anim,
  drop `drops` into inventory, then free the node. Cozy framing — keep it gentle (no gore particles;
  a few soft puffs). Optionally require a crafted tool (e.g. a spear) to hunt.
- **Rich drops** using `icons_raw_meat_bones.png`: don't just drop "meat". Example loadouts —
  hare → `raw_meat` (small) + `bone`; deer → `venison` + `antler` + `bone`; grouse → `raw_poultry`.
  Raw meat then cooks at the campfire (Phase 7 recipe) into `icons_food` dishes. Bones/antlers feed
  tool/decor recipes. Define all drops in the `AnimalData.drops` array so it's data, not hardcoded.
- Spawn a small population around the island; respawn slowly over time (day-based cap).

## Definition of done
- Animals wander naturally, flee when the player approaches, using navigation (no wall-hugging jank).
- Can hunt for food; drops enter inventory; population respawns slowly.
- Animal definitions are data; adding a new animal = new `AnimalData` + `SpriteFrames`.

## Do NOT
- Add predators/attacks on the player (keep cozy). Boar's attack anim can wait or be a one-off
  "defensive" flavour at most — confirm with me before adding any aggression.

Update ROADMAP + CLAUDE.md.
