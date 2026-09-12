# Phase 2 — Island World, Tiles, Camera & Y-Sort

**Goal:** a real island to walk on — a square-grid TileMap with beach/grass/forest/rock zones,
water around the edge, working collision, and correct Y-sorting so the player passes behind/in
front of scenery.

## Approach
- Root world scene `scenes/main/World.tscn` (`Node2D`), with **Y-sort enabled** on the layer
  that holds player + scenery.
- Use a **TileMapLayer** (Godot 4.3+) or `TileMap` for ground. Separate layers:
  - `Ground` (beach/grass/dirt/rock) — no collision
  - `Water` (animated shoreline using the dungeon pack water sheets) — collision (block player)
  - `Props`/`YSortLayer` — trees/bushes as Y-sorted nodes (added in Phase 5; leave hooks)
- Island shape: hand-place for now, OR generate with `FastNoiseLite` (Perlin/Simplex) into a
  roughly circular island (distance-from-centre falloff so it's surrounded by water). Keep it
  **medium-large** but not huge. Make generation a separate script so it's swappable.

## Tiles
- Build a `TileSet` from placeholder or the dungeon pack floor/water sheets. Beach = sandy edge
  ring, grass interior, patches of rock. Don't over-invest in autotiling yet — a basic terrain
  set with a few tiles is enough to prove the loop.
- Water tiles get a physics/collision layer so the player can't walk off the island.

## Camera & bounds
- Camera2D follows the player (already on Player). Set `limit_*` to the island bounds so the
  camera doesn't show endless void, OR let water fill the frame — your call, keep it tidy.

## Y-sort proof
- Place a few trees/tall props (placeholder sprites at correct origin = base of trunk) so I can
  walk behind and in front and see sorting work.

## Definition of done
- Walkable island, water blocks movement at the edges.
- Y-sorting visibly correct against tall props.
- Generation (if used) is in its own script and produces a sensible island each run (or a fixed
  seed for now).

## Do NOT
- Add harvestable logic to props yet (Phase 5).
- Add day/night tint (Phase 3).

Update ROADMAP + CLAUDE.md when done.
