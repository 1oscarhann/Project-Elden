# CLAUDE.md — Cozy Island Survival

> This file is read automatically by Claude Code at the start of every session.
> It is the source of truth for the project. Keep it updated as things change.

## What we're building

A **cozy 2D angled-top-down (2.5D, Stardew Valley-style) pixel-art survival game** in **Godot 4.x with GDScript**. Deserted island setting, relaxed pace, **no permadeath**. The only real pressure is keeping a **campfire fuelled at night** via a wood-pile stockpile — if it burns out, the player just gets **cold** (a stat penalty), never a game over.

Core fantasy: gather across a full resource web → work up a proper crafting tree → hunt passive animals → build a Stardew-style grid base whose **interiors are bigger inside than outside**. This is a for-fun project, prioritising **feel and polish over feature bloat**.

## Hard rules (do not violate)

1. **NOT true isometric.** Use a normal **square-grid TileMap** with **Y-sorting** enabled. The isometric *look* comes purely from the angled art, never from the tile projection or movement axes. Movement is standard 4/8-directional on a square grid.
2. **Build ONE PHASE AT A TIME.** Never scaffold multiple phases in one go. Each phase must be complete, runnable, and confirmed by me before moving on. Phases live in `docs/phases/`.
3. **Data-driven everything.** Items, resources, and recipes are defined in data (`.tres` custom `Resource` files, or JSON), never hardcoded in logic. The resource web and crafting tree must be expandable by adding data files, not by editing systems code.
4. **Signals over hard references.** Systems communicate via signals and autoload singletons. No reaching across the scene tree with `get_node("../../Thing")`.
5. **Delta-based and framerate-independent.** All movement, timers, and depletion use `delta`.
6. **Cozy, not combat.** Use the **Unarmed** player sprites. There is no player-vs-enemy combat. Animals are passive/huntable. Repurpose the "attack" swing as the **harvest/chop** animation if needed.
7. **Keep it clean.** Commented, modular, one responsibility per script. Small scenes composed together.

## Tech stack

- **Engine:** Godot 4.x, GDScript (Forward+ or Mobile renderer, 2D)
- **Rendering:** pixel-perfect — set texture filter to Nearest, snap 2D transforms/vertices to pixel, integer-scaled viewport
- **Persistence:** JSON save files in `user://`
- **Target:** desktop first; keep web export viable (avoid threads/features that break HTML5)

## Autoload singletons (set up in Project Settings → Autoload)

| Name        | Script                          | Responsibility |
|-------------|---------------------------------|----------------|
| `GameState` | `res://scripts/globals/game_state.gd` | Player stats (health, warmth, hunger), current day/phase, high-level flags |
| `Inventory` | `res://scripts/globals/inventory.gd`  | Item stacks, add/remove, signals on change |
| `DayNight`  | `res://scripts/globals/day_night.gd`  | In-game clock, day counter, day/night signals |
| `Crafting`  | `res://scripts/globals/crafting.gd`   | Recipe lookup, can-craft checks, crafting execution |
| `ItemDB`    | `res://scripts/globals/item_db.gd`    | Loads all item/resource `Resource` files at boot, lookup by id |

Add each singleton only in the phase that first needs it (see phase docs). Don't create empty ones early.

## Project structure (target)

```
res://
├── CLAUDE.md
├── project.godot
├── assets/                  # imported art (see docs/ASSETS.md for what's what)
│   ├── characters/
│   ├── animals/
│   ├── trees/
│   ├── bushes/
│   ├── tiles/
│   ├── objects/             # campfire, fire animation, doors, chests
│   └── icons/               # item/food/tool/ore icons
├── scenes/
│   ├── main/                # Main.tscn, World.tscn
│   ├── player/              # Player.tscn
│   ├── world/               # resource nodes, campfire, buildings, interiors
│   ├── entities/            # animals
│   └── ui/                  # hud, inventory, crafting, build menu
├── scripts/
│   ├── globals/             # autoload singletons
│   ├── player/
│   ├── world/
│   ├── entities/
│   └── ui/
├── resources/               # data-driven .tres files
│   ├── items/               # ItemData resources
│   └── recipes/             # RecipeData resources
└── docs/
    ├── ASSETS.md            # asset manifest (frame sizes, paths, licence)
    ├── ROADMAP.md           # the 10 phases at a glance
    └── phases/              # one detailed spec per phase
```

## Player sprite facts (verified — use these exact numbers)

The character pack is `CraftPix free`. Use the **Unarmed / Without_shadow** sheets.

- **Frame size: 64×64 px.**
- Sheets are **grids: 4 rows = 4 directions in order `down, left, right, up`**, columns = animation frames.
- Frame counts per sheet:
  - `Unarmed_Idle`  — 12 cols × 4 rows
  - `Unarmed_Walk`  — 6 cols × 4 rows
  - `Unarmed_Run`   — 8 cols × 4 rows
  - `Unarmed_Hurt`  — 5 cols × 4 rows
  - `Unarmed_Death` — 7 cols × 4 rows
- The character art sits small inside the 64px cell with padding — that's expected, keep the full 64px frame so animations line up.
- There is **no left/right flip needed** — the sheet already contains separate left and right rows. (You *may* instead use only `down/side/up` and flip the side row to save memory; either is fine, pick one and be consistent.)

## Asset licence

All art is **CraftPix free-licence** → **attribution is required**. Maintain a `CREDITS.md` listing each pack. Do not ship without it.

## Workflow with me

- At the start of a phase, read the matching `docs/phases/phaseNN_*.md` in full before writing code.
- Tell me exactly which files you'll create/modify before doing it.
- After a phase, update `docs/ROADMAP.md` progress and note anything that changed here in CLAUDE.md.
- If a phase spec conflicts with reality (e.g. asset differs), stop and flag it — don't silently improvise.

## Current status

**Phase 0 (project setup) not yet started.** Begin with `docs/phases/phase00_setup.md`.
