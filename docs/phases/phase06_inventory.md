# Phase 6 — Inventory (Data-Driven Items)

**Goal:** a real inventory backing everything — stackable items defined in data, a hotbar and a
full inventory panel, with icons from the CraftPix icon sheets.

## Data model
- `scripts/world/item_data.gd` → `class_name ItemData` (`Resource`): `id`, `display_name`, `icon`
  (Texture2D / AtlasTexture), `max_stack`, `category` (enum: material/food/tool/misc), `description`,
  and optional `stats` dict (e.g. food restores hunger).
- Create `.tres` items in `resources/items/`: `wood`, `stone`, `fibre`, `berry`, plus any drops
  from Phase 5. Icons pulled from `res://assets/icons/` (slice the sheets into AtlasTextures).
- `ItemDB` autoload (`scripts/globals/item_db.gd`): scans `resources/items/` at boot, builds a
  `Dictionary` id → ItemData. Everything looks items up by id.

## Inventory autoload
- `Inventory` (`scripts/globals/inventory.gd`):
  - Backing store: array of slots `{ item_id, count }` with a fixed size (e.g. 24) + hotbar (e.g. 8).
  - Methods: `add_item(id, n) -> int (leftover)`, `remove_item(id, n) -> bool`, `count(id) -> int`,
    `has(id, n) -> bool`. Respect `max_stack`, fill existing stacks first, then empty slots.
  - Signal `inventory_changed` on any mutation. UI listens to this.
- Retro-fit Phase 4 (campfire wood) and Phase 5 (drops) to use `Inventory` instead of placeholders.

## UI
- `scenes/ui/InventoryPanel.tscn`: a grid of slot buttons showing icon + count; toggle open/close
  with a key (e.g. Tab/I). Pause-free (cozy game). Tween the panel open/closed.
- `scenes/ui/Hotbar.tscn`: always-visible row of the first N slots; number keys select.
- Drag-to-move or click-to-move between slots is nice-to-have, not required this phase.
- Use the real icons. Keep layout clean; heavy polish in Phase 10.

## Definition of done
- Harvesting adds real items; campfire consumes real wood; counts stack and cap correctly.
- Inventory + hotbar render with correct icons and update live via signals.
- Items are defined purely as data; adding a new item = new `.tres`, no code change.

## Do NOT
- Implement crafting yet (Phase 7) — but ensure `has`/`remove_item` are solid, since crafting
  depends on them.

Update ROADMAP + CLAUDE.md.
