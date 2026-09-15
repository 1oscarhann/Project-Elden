# Phase 11 — Hunger & Thirst

**Goal:** two new survival stats — hunger and thirst — that deplete over time and are restored
by eating and drinking. Same cozy, soft-penalty philosophy as warmth: never death, just gentle
pressure that gives food and water an actual purpose. Build this BEFORE Phase 10 (polish),
since Phase 10 should polish a complete survival loop, not a partial one.

## Why now
You already have raw meat, cooked food, and item icons (Phases 5/7/9) with nothing consuming
them yet. Hunger gives them purpose. Thirst adds a second resource loop (freshwater) that isn't
covered by anything else. Both close real gaps identified during playtesting.

## Stats (extend `GameState`)
Add to the existing `scripts/globals/game_state.gd` (same pattern as `warmth`):
- `hunger: float` (0..100, start 100), signal `hunger_changed(value)`
- `thirst: float` (0..100, start 100), signal `thirst_changed(value)`
- Both drain slowly over time via `delta` (expose `hunger_drain_rate`, `thirst_drain_rate` as
  `@export`/tunable constants).

## Soft penalties (cozy — never death)
When hunger or thirst is low (e.g. below ~20), apply gentle, stacking penalties — pick from:
- Faster warmth drain (hunger/thirst makes you feel the cold more)
- Slight movement speed reduction
- A subtle visual cue (desaturation, a small icon pulse on the HUD)
Do NOT implement damage or death from hunger/thirst. If both hit 0, the penalties simply cap out
at their maximum — nothing worse happens. This matches the warmth system's philosophy exactly.

## Restoring hunger — eating
- Any `ItemData` with `category == FOOD` can be consumed from the inventory/hotbar (e.g. press a
  "consume" key while an eligible item is selected, or right-click in the inventory UI).
- Add a `hunger_restore` (and optionally `thirst_restore`, for things like fruit) value to
  `ItemData` for food items. Cooked food should restore more than raw (matches Phase 7's cooking
  incentive). Eating removes 1 from the stack and applies the restore via signal to `GameState`.
- Small juice: a soft "munch" sound/particle and a floating "+hunger" style pickup-text, consistent
  with the harvest-hit feedback style from Phase 5.

## Restoring thirst — drinking (needs a source)
Sea water does NOT quench thirst (it's salt water) — this is a deliberate design constraint that
forces a real freshwater loop. Implement ONE of these (pick the simpler to build first; the other
can be added later):
1. **Freshwater feature**: place one or more freshwater ponds/springs on the island (reuse world
   generation — a small inland water feature distinct from the sea, or just permit drinking from
   any water tile that isn't classified as "ocean"). Player interacts at the water's edge to drink
   directly (instant thirst restore, no inventory item needed).
2. **Craftable container**: a `waterskin`/`bottle` item (add a hand-craft recipe in the existing
   Crafting system) that the player fills by interacting with a freshwater source, then drinks
   from anytime via the inventory (consumes the fill, keeps the container, refill by
   interacting with water again).
Recommend implementing (1) first since it's simpler, then layering (2) on top later if wanted.

## HUD
- Extend the existing HUD (`scenes/ui/HUD.tscn`, themed per Phase 6's cozy UI) with a **hunger
  bar** and **thirst bar** alongside the warmth bar. Use the pack's bar/slider style. Icons from
  the existing `icons_food.png` (a drumstick/apple-style icon) for hunger. For thirst, there's no
  dedicated water-drop icon — reuse a blue flask/potion icon from `icons_potions_flasks.png` as
  the thirst bar icon instead of sourcing new art.

## Definition of done
- Hunger and thirst drain over time, visible on the HUD.
- Eating food from inventory restores hunger (cooked > raw); some foods can restore thirst too.
- At least one way to restore thirst from a freshwater source exists and sea water does not work.
- Low hunger/thirst produces a soft, non-lethal penalty; nothing worse happens at zero.
- All values (drain rates, restore amounts, penalty thresholds) are tunable, not hardcoded.

## Do NOT
- Add death, damage, or game-over from hunger/thirst.
- Let sea water quench thirst.
- Overbuild the drinking mechanic — pick ONE approach (pond or container) to ship; add the other
  later if it's still wanted.

When done, update `docs/ROADMAP.md` (add Phase 11 between 9 and 10) and `CLAUDE.md`'s status.
Then proceed to Phase 10 (polish), which should now polish hunger/thirst feedback too (juice on
eating/drinking, HUD bar animations) alongside everything else in that phase.
