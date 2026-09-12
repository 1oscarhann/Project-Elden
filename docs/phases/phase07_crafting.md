# Phase 7 — Crafting Tree

**Goal:** a proper, data-driven crafting system with ingredient dependencies (a real tree, not a
flat list), plus a craft menu. Depends on Phase 6 inventory.

## Data model
- `scripts/world/recipe_data.gd` → `class_name RecipeData` (`Resource`):
  `id`, `result_item_id`, `result_count`, `ingredients` (array of {item_id, count}),
  `required_station` (optional, e.g. "campfire"/"workbench"/null for hand-craft),
  `unlocked_by_default` (bool), `category`.
- Create `.tres` recipes in `resources/recipes/`. Build an actual **tree** of dependencies, e.g.:
  - `plank` ← 1 wood (hand)
  - `rope` ← 2 fibre (hand)
  - `campfire_kit` ← 3 wood + 1 stone (hand)
  - `workbench` ← 4 plank + 2 stone (hand)
  - `torch` ← 1 plank + 1 fibre (hand)
  - `cooked_meat` ← 1 raw_meat (requires campfire)  [icons: raw from icons_raw_meat_bones, cooked from icons_food]
  - `warmth_tonic` ← 1 berry + 1 fibre (requires campfire)  [icon from icons_potions_flasks] — drink to restore warmth away from fire
  - `bone_tool` ← 1 bone + 1 plank (hand)  [bone from icons_raw_meat_bones] — example of using animal by-products
  - deeper items require a `workbench` station → creates progression
- `Crafting` autoload (`scripts/globals/crafting.gd`): loads recipes at boot; `can_craft(recipe)`
  checks `Inventory.has` for all ingredients (+ station availability); `craft(recipe)` removes
  ingredients and adds result via `Inventory`. Signal `crafted(recipe)`.

## Stations
- A recipe with `required_station` can only be crafted when the player is near that station
  (reuse an Area2D on the campfire/workbench, set a `GameState.current_station` or pass context to
  the craft menu). Hand-craft recipes need no station.

## UI
- `scenes/ui/CraftMenu.tscn`: list recipes (filter by station/category), show ingredients with
  have/need counts (greyed if uncraftable), a Craft button. Live-update as inventory changes.
- Open near a station, or a global hand-craft menu for `required_station == null` recipes.

## Definition of done
- Can craft hand recipes anywhere; station recipes only near the station.
- Ingredient dependencies work (must craft planks before workbench, etc.) — a real tree.
- Adding a recipe = new `.tres`, no code change. Craft menu reflects craftability live.

## Do NOT
- Build placement of crafted stations in the world yet — that's Phase 8. Crafting a `workbench`
  can just give a `workbench` item for now; placing it comes next.

Update ROADMAP + CLAUDE.md.
