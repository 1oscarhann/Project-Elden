# Phase 5 — Resource Nodes & Harvesting Juice

**Goal:** trees, rocks and bushes you can harvest for materials, with satisfying feedback
(squash-stretch, particles, screen shake) and regrowth. Completes the cozy vertical slice.

## Assets
- Trees: `res://assets/trees/` (palm/fruit/normal + `Broken_*` for harvested state, plus shadows)
- Bushes: `res://assets/bushes/` — 3 growth stages `_1/_2/_3` per bush → use as regrow states
- Rocks: use dungeon-pack objects or a simple placeholder rock sprite

## Data-driven harvestables
Define a small `Resource` script `scripts/world/harvestable_data.gd` (`class_name HarvestableData`)
with fields: `id`, `display_name`, `sprite`, `harvested_sprite`, `drops` (array of {item_id, min,
max}), `hits_required`, `regrow_seconds`, `growth_stage_sprites` (optional for bushes).
Create a few `.tres` instances in `resources/items/` or `resources/harvestables/`:
`tree_palm`, `tree_fruit`, `bush_berry`, `rock`.

## Scene: `scenes/world/Harvestable.tscn`
```
Harvestable (Node2D)              # script: scripts/world/harvestable.gd  (@export HarvestableData)
├── Sprite (Sprite2D)             # current visual (full/harvested/stage)
├── Shadow (Sprite2D)
├── Interact (Area2D) + Collision # player enters + presses interact to harvest
└── (optional) Body collision     # trunk blocks walking
```
Behaviour:
- On interact: play player's **harvest/chop** animation, apply 1 hit, squash-stretch tween on the
  node, spawn a small particle burst, tiny screen shake. When `hits_required` reached: swap to
  `harvested_sprite` (or drop a growth stage), drop items into inventory (or `GameState` placeholder
  if Phase 6 not done), start `regrow_seconds` timer, then restore.
- Bushes: cycle `growth_stage_sprites` instead of a broken sprite.

## Screen shake
- Add a reusable camera shake (trauma-based, decays over time) callable from any harvest hit.
  Put it on the Player's Camera2D or a small autoload helper. Keep it subtle — cozy, not violent.

## Spawning
- Scatter harvestables across the island (hook into the Phase 2 world/props layer). Random or
  noise-based placement on grass/forest tiles, avoiding water. Keep them Y-sorted.

## Definition of done
- Can harvest trees/rocks/bushes; correct drops appear; nodes show harvested state then regrow.
- Harvesting feels good: squash-stretch + particles + subtle shake + player swing anim.
- Harvestable definitions live in data files, not hardcoded.

## Do NOT
- Build the full crafting tree (Phase 7) — just produce raw materials (wood, stone, fibre, food).

Update ROADMAP + CLAUDE.md. **This is the vertical-slice checkpoint — we playtest here.**
