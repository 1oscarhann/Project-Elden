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

- **Engine:** Godot 4.7, GDScript (**GL Compatibility** renderer, 2D — chosen in Phase 0 to keep the HTML5 export viable; Forward+ buys a 2D pixel game nothing)
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
├── tools/                   # one-off dev scripts (tile generator); not shipped
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
- **Measured in Phase 1 (exact, verified with `Image.get_used_rect()` on every frame):** the art
  occupies only ~17x25 px inside the 64x64 cell. **The feet sit on cell-y 44 on every row of every
  sheet.** So with `centered = true`, an `offset` of `(0, -12)` puts the feet exactly on the node
  origin — which is what Y-sorting reads. Reuse that number for any new Unarmed sheet.
- There is **no left/right flip needed** — the sheet already contains separate left and right rows. (You *may* instead use only `down/side/up` and flip the side row to save memory; either is fine, pick one and be consistent.)

## Asset licence

All art is **CraftPix free-licence** → **attribution is required**. Maintain a `CREDITS.md` listing each pack. Do not ship without it.

## Workflow with me

- At the start of a phase, read the matching `docs/phases/phaseNN_*.md` in full before writing code.
- Tell me exactly which files you'll create/modify before doing it.
- After a phase, update `docs/ROADMAP.md` progress and note anything that changed here in CLAUDE.md.
- If a phase spec conflicts with reality (e.g. asset differs), stop and flag it — don't silently improvise.

## Current status

**Phase 5 complete — this is the vertical-slice checkpoint. Play it before Phase 6.**
Next up: `docs/phases/phase06_inventory.md`.

### Regression suite — run this after ANY change

    godot --headless --path . res://tools/regression_check.tscn

31 checks across every phase built so far; exits non-zero on failure. It exists because a
careless edit silently deleted the entire warmth system (`_process`, `warmth_rate`, `is_warmed`,
`speed_factor`, …) and that phase's own tests never touched warmth, so it went unnoticed until a
HUD call blew up. **Do not skip it.**

### Phase 5 notes

- **Harvestables are fully data-driven.** `HarvestableData` (+ `HarvestDrop`) `.tres` files in
  `resources/harvestables/` carry sprites, drop tables, hits, regrow time, draw scale, particle
  colour, and *their own spawn terrains and chance*. Adding a tree, bush or rock is a new `.tres`
  and nothing else — `world.gd` just offers each tile to each entry in turn, first match wins.
- **Regrowth is one mechanism, not two.** Everything is a stage ladder: a staged node (the bushes
  ship as three sizes) climbs its own stages, and a simple node is just the two-rung ladder
  `[harvested, full]`. One code path covers both.
- **Origins are measured, never hardcoded.** `SpriteAnchor.base_offset()` reads each texture's
  alpha bounds and caches it, so new art anchors its base on the origin automatically — that is
  the point Y-sorting compares. It re-anchors per stage, since the bush sizes differ in height.
- **Feel:** squash-stretch tween (elastic settle), one-shot particle burst tinted per material,
  and trauma-based camera shake on `player_camera.gd` (`add_trauma`, squared so small knocks stay
  gentle). The player swing is driven by group call — harvestables never hold a player reference.
- **The chop animation is the Sword_attack sheet**, per CLAUDE.md rule 6. ⚠️ He is visibly
  swinging a *sword* at trees, which reads oddly for a no-combat game. Replace with axe art when
  convenient — the SpriteFrames is regenerated from the sheet grid, so it is a one-file swap.
- **⚠️ Tree art is out of scale with the tileset.** The CraftPix trees are ~74px tall against a
  16px grid and a 24px player; at scale 1.0 they bury him completely. `sprite_scale` in each
  `.tres` is set to **0.55** as a stopgap. The Sprout Lands pack has matching 32x32 trees, stumps
  and bushes (`assets/objects/sprout_objects.png`) — switching is a pure `.tres` edit, no code.
- **Boulders are the stone source** (`resources/harvestables/rock.tres`, "Boulder"), scattered on
  sand, grass and woodland at a 0.02 chance — about 90 across the island. There is no rock
  terrain to mine.
- **Density is tuned to ~378 nodes, roughly 1 per 10 land tiles.** The first pass at 824 was a wall
  of foliage with the player invisible inside it.
- **Materials:** `GameState` now holds a `_materials` dictionary behind
  `add_material` / `spend_material` / `count_of` / `all_materials`, with `wood` kept as a
  delegating alias so the campfire is untouched. Phase 6 replaces the lot with `Inventory`.

### Phase 4 notes

- **`Campfire.tscn` / `campfire.gd` is fully self-contained and instanceable** — it never reaches
  for the player or the world. Phase 8 can place them freely.
- **The fire sheet is `fire_animation.png`, 4 cols x 6 rows of 44x48 cells** (NOT a 16px grid, and
  rows 3-5 are *not* duplicates of 0-2 despite identical alpha bounds). Each column is a different
  fire size, which `campfire_frames.tres` maps to fuel stages:
  col 0 `ember`, col 1 `low`, col 3 `medium`, col 2 `high`. Sprite `offset = (0, -16)` puts the
  log base on the origin for Y-sorting. **Only the fire is used from that pack.**
- **Warmth wiring uses the Phase 3 hook untouched:** `_refresh()` is idempotent and recomputes
  `player_in_radius AND is_lit`, so a fire *dying under a standing player* correctly stops warming
  them. `_exit_tree` hands the heat source back so a freed fire cannot leak one.
- **Balance (recompute if `day_length_seconds` changes):** a 600s day gives a **252s night** and a
  48s dusk. `burn_rate = 0.5` makes a full 100-fuel fire last **200s**, so one mid-night top-up is
  needed — about **5 logs a night** at `wood_value = 25`. The original 1.6 needed 16 logs a night,
  which is a treadmill, not a cozy game. `night_drain` was softened 4.0 -> **2.5** (40s from warm
  to cold away from a fire) now that there is somewhere to run to.
- **`GameState.wood` is a placeholder** until Phase 6's `Inventory`. It is backed by `_wood` with a
  setter so **even a direct assignment emits `wood_changed`** — without that the HUD silently
  desynced from the real count (caught in a screenshot, not a test).
- **A dead fire leaves faint cold coals** rather than vanishing. Spec allowed "embers optional";
  without them the pit is invisible at night and unfindable, which breaks the loop.
- **World-space `Label`s need an explicit small font.** At camera zoom 2 the default 16px font
  renders at 32px and swamps the screen. The campfire prompt uses `font_size = 8` plus an outline.

### Phase 3 notes

- **Autoloads now live** (first two of the five): `DayNight` then `GameState`, in that order —
  `GameState` reads `DayNight.phase` in `_ready`, so the ordering in `project.godot` matters.
- **`DayNight`** owns `time_of_day` (0..1), `day`, `phase` and emits `ticked` / `phase_changed` /
  `day_passed`. `advance(fraction)` is deliberately separate from `_process` so tests and debug
  keys can step time without waiting. `day_length_seconds` defaults to **600** (10 real minutes).
- **`GameState.warmth`** drains at night (-4/s) and dusk (-1.5/s), recovers by day (+8/s).
- **The Phase 4 campfire hook already exists and is tested:** call
  `GameState.add_heat_source()` / `remove_heat_source()` from an `Area2D`'s
  `body_entered`/`body_exited`. Being in any heat source overrides the clock entirely (+20/s).
  The warmth maths never needs to know what a campfire is.
- **Cold is soft, and enforced to be:** `speed_factor()` eases to a floor of **0.6** and is
  asserted never to reach zero. `chill()` (0..1) drives the HUD's blue overlay. No death, ever.
- **Sky tint is data, not code:** `sky_tint.gd` is a `CanvasModulate` that samples an exported
  `Gradient` (authored as a SubResource in `World.tscn`) at `time_of_day`. Retune the look by
  dragging colour stops. Night bottoms out at luminance ~0.47 — cozy, not pitch black.
- A `PointLight2D` on the player gives a soft lantern pool at night so nothing is ever fumbling.
- **Third Godot gotcha, the big one:** running a test with `--script res://foo.gd` **does not
  register autoload singletons**, so any script referencing `DayNight`/`GameState` fails to even
  compile ("Identifier not found"). Run verification as a real scene instead
  (`godot --path . res://_test.tscn` with a `Node` script that instantiates `Main.tscn`).
  The `--script` trick only works for phases with no autoloads.

### Phase 2 notes

- **The dungeon pack (169442) is MOSTLY dropped** — wrong art style for a sunny island.
  **Allowed exceptions (owner's call, Phase 3):** the **fire animation**, **doors** and **chests**
  only. Nothing else from that pack — in particular its wall/floor and water tiles stay out, so
  Phase 8 still needs interior tile art. Re-add the pack to `CREDITS.md` when the fire is used.
- **Terrain tiles come from the Sprout Lands Basic pack by Cup Nooble** (a real 16x16 pack — an
  earlier CraftPix-style reference was only ever a lossy preview and has been dropped).
  Source sheets live in `assets/tiles/sprout_lands/`; `tools/build_terrain_atlas.gd` composites
  the exact cells below into `assets/tiles/island_terrain.png`, and
  `tools/build_tileset.gd` rebuilds `island_terrain.tres` from it. Both are Godot scripts, run with
  `godot --headless --path . --script res://tools/<name>.gd`.
  | row | terrain | sheet | cells |
  |-----|---------|-------|-------|
  | 0 | deep water | `Water.png` | (0-3,0) darkened to 0.62 |
  | 1 | shallow water | `Water.png` | (0-3,0) |
  | 2 | sand | `Tilled_Dirt.png` | (0,5) (1,5) (2,5) (0,6) |
  | 3 | grass | `Grass.png` | (0,5) (1,5) (2,6) (3,6) |
  | 4 | forest | `Grass.png` | same, darkened to 0.80 |
  The pack has no dark grass and only one water tile, hence the two darkened rows. Cells were
  chosen by scanning every 16px cell for full opacity — the sheets are mostly autotile blobs on
  transparency, and only rows 5-6 of `Grass`/`Tilled_Dirt` hold solid interior tiles.
- **There is NO hill or stone terrain, by design (owner's call).** The island is sea, beach,
  grass and woodland — five terrains, five atlas rows. **Stone comes from boulders scattered on
  the ground as `Harvestable` nodes**, not from a mined biome. `Hills.png` stays committed for
  possible Phase 8 cliff autotiles but nothing currently reads it.
- **⚠️ Sprout Lands is NON-COMMERCIAL only** and forbids NFT/AI-training use. The CraftPix packs
  allow commercial use; this one does not, so the project as a whole is now non-commercial.
  Full terms are reproduced in `CREDITS.md` as the licence requires. Swap these tiles before
  ever selling anything.
- **The two water rows are a single ANIMATED tile each**, not four variants — their four columns
  are animation frames. `world.gd` therefore paints water at column 0 always, and picks a random
  column only on land. Water also carries the collision that stops the player leaving the island.
- **Tile size is 16x16**, chosen to suit the ~24px-tall character.
- **World structure:** `Water` and `Ground` are two TileMapLayers holding *disjoint* cell sets,
  so the water layer's collision only ever blocks real water. `Props` (y-sorted) holds the trees
  and the player.
- **Generation is split in two on purpose:** `island_generator.gd` is a `Resource` that returns a
  terrain grid and knows nothing about TileMaps; `world.gd` does all the painting. Swap either
  without touching the other. Seed is fixed (`20240612`); flip `randomize_seed` for a new island.
- **Tree origins are measured at runtime** from each texture's alpha bounds, so new tree art
  dropped into `assets/trees/` gets a correct trunk-base origin with no per-file constants.
- **Scenery keeps a rect-shaped clearing at spawn**, not a radius — a canopy is ~74px tall, so a
  tree several tiles south still draws over the player's head.
- **Two Godot gotchas learned the hard way, do not repeat them:**
  1. `@export var x: SomeNode` serializes as a **NodePath and is not reliably resolved** by the
     time `_ready()` runs — it came back null. Use `@onready var x := $Child` for a scene's own
     children. Resource exports (the generator, texture arrays) bind fine.
  2. In a `SceneTree._initialize()` script, `root.add_child()` does **not** put the node in the
     tree synchronously — `_ready()` fires a frame later. Any verification script must assert
     from `_process()`, not `_initialize()`, or it silently measures an empty scene.
- **Camera:** `player_camera.gd` joins the `player_camera` group; the world hands it bounds and a
  `snap_to_target()` via `call_group`, so neither side needs a path to the other. The snap matters
  — without it the camera visibly glides in from the origin on load.

### Phase 1 notes

- **Input actions** (in `project.godot`, bound by *physical* keycode so AZERTY/QWERTZ work):
  `move_up/down/left/right` = WASD + arrows, `run` = Shift.
- **Animation is `SpriteFrames` + a play-on-change string swap**, not an `AnimationTree`.
  `scenes/player/player_frames.tres` holds 12 animations (`idle|walk|run` x `down|left|right|up`,
  104 atlas regions). It is generated from the sheet grid, so regenerate rather than hand-edit.
  Idle 6 fps, walk 10 fps, run 12 fps, all looping.
- **`player_frames.tres` lives in `scenes/player/`, not `resources/`** — `resources/` is reserved
  for data-driven *game data* (items, recipes). A SpriteFrames is scene-coupled art config.
- **All 4 direction rows are used; nothing is flipped.** Pick this consistently for new sprites.
- **The Player node is NOT `y_sort_enabled`; its parent `World` is.** Y-sorting the player itself
  would sort its own Shadow against its Sprite. The world sorts the player as one unit, which is
  correct because the player's origin is on its feet.
- `motion_mode = FLOATING` on the `CharacterBody2D` — top-down has no floor/gravity concept.

### Phase 0 notes (decisions that deviate from the spec — read before Phase 1)

- **`project.godot` was hand-authored**, not generated by the editor. The phase spec assumed
  this was impossible; it isn't — it's a plain INI file and Godot 4.7 loads it fine. Verified by
  booting the project headless (all settings assert green, `Main.tscn` loads, clean run + exit 0).
- **Renderer is GL Compatibility**, not Forward+ (see Tech stack above). Web export stays possible.
- **Empty dirs use `.gitkeep`, NOT `.gdignore`.** The spec suggested `.gdignore`, but that makes
  Godot *ignore the folder entirely* — assets inside would never import. `.gitkeep` is purely for
  git, which can't track empty directories. Delete a `.gitkeep` once real files land in its folder.
- **Pixel-art import is project-wide via `[importer_defaults]` in `project.godot`** (lossless,
  no mipmaps, no alpha-border fix, no 3D detection). This is the "shared import preset" the spec
  asked for: **any texture dropped into `assets/` imports as pixel art automatically** — never
  hand-set Nearest on a file again. Confirmed in the generated `.png.import` files.
- **Display:** 640x360 base viewport, stretch `viewport` / `keep` / **`integer`** scale mode,
  `default_texture_filter = 0` (Nearest), 2D transform + vertex snapping on.
- **No assets copied yet** (per the spec's "Do NOT"). The 5 CraftPix zips sit in `raw_assets/`;
  `setup_assets.sh` paths were verified against the real zip contents and all match. Pull assets
  per-phase. Phase 1 needs only `Unarmed_{Idle,Walk,Run}_without_shadow.png` + `shadow_single.png`.
- **No autoloads exist yet**, by design. Add each one in the phase that first needs it.
