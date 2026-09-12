# Phase 8 — Grid Base Building & Interiors

**Goal:** place crafted structures on a grid (Stardew-style), and enter buildings whose interiors
are separate, larger scenes ("bigger on the inside").

## Placement
- A **build mode** toggled by a key. While active: show a grid-snapped ghost preview of the
  selected buildable (semi-transparent, green=valid / red=blocked). Click to place if the tile is
  free and the player has the item/materials; placement consumes the item from `Inventory`.
- Snap to the world's square grid (match TileMap cell size). Prevent placing on water / on the
  player / on existing objects.
- Buildables are data too: extend item/`ItemData` with a `placed_scene` (PackedScene) so "use"
  in build mode instances that scene. Start with: campfire, workbench, a wall/fence, a door/house.

## Buildable scenes
- Reuse `Campfire.tscn` (now placeable). Add `Workbench.tscn` (crafting station). Add a simple
  `Wall.tscn`/`Fence.tscn` (collision + Y-sorted sprite).
- `House.tscn` (exterior): a building sprite with a **door Area2D**. Entering the door triggers a
  scene/room transition.

## Interiors (bigger inside)
- Each building links to an **interior scene** (`scenes/world/interiors/*.tscn`) built from the
  dungeon-pack walls/floors. The interior is intentionally larger than the exterior footprint.
- Transition: on entering the door, fade out, swap the active room (either load a separate scene
  or move the player + camera to an interior area of the world), spawn player at the interior
  entrance. A matching interior door returns them outside. Keep a clean `RoomManager` or use
  `get_tree().change_scene_to_packed` with saved player state — your call, but make it reusable.
- Interiors are safe/warm (no warmth drain), reinforcing "home".

## Definition of done
- Build mode places grid-snapped structures, consuming inventory, blocking invalid spots.
- Placed workbench/campfire function as stations.
- Can enter a house via its door into a larger interior and exit back out; transition is smooth.

## Do NOT
- Over-scope interior furnishing/decoration systems — one working house + interior proves it.

Update ROADMAP + CLAUDE.md.
