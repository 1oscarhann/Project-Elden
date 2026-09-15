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

**PROJECT v1 COMPLETE — all ten phases built, 188 regression checks green.** What is left is
content and a build: more recipes, more islands, seasons, a desktop/web export and an itch.io
page. All of that is data or packaging, not new systems.

### Phase 10 notes

- **Eight autoloads now**, in this order: `DayNight`, `GameState`, `ItemDB`, `Inventory`,
  `Crafting`, **`SaveManager`**, **`Settings`**, **`Audio`**. The order is load-bearing:
  `Settings.apply()` writes `DayNight.day_length_seconds`, and `Audio._ready()` connects to
  `DayNight.phase_changed`, `Inventory.item_gained` and `Crafting.crafted`.
- **The game now boots to `scenes/ui/MainMenu.tscn`**, not `Main.tscn`.
- **Saving is a protocol, not a switchboard.** Every participant exposes
  `save_data() -> Dictionary` / `load_data(Dictionary)` and `SaveManager` only posts those
  dictionaries around — it never learns what warmth or a hotbar slot *is*. Adding a system to the
  save is two methods on that system and one line in `save_game`.
- **⚠️ The terrain is NOT in the save — the SEED is.** The island is a pure function of the seed,
  so only what the player changed is written: buildings placed, trees chopped, fires fed.
  Measured: **a played session saves at 1.5 KB**, versus roughly a megabyte for 96x96 cells across
  five layers. `World.load_data` rebuilds the island only if the saved seed differs.
- **Saves are keyed by CELL**, because scenery is jittered only *within* its own tile
  (±4px x, ±3px y on a 16px grid), so `world_to_cell(node.position)` round-trips exactly. JSON
  object keys must be strings, hence `"%d,%d"`.
- **Only harvestables that differ from generated state are written** (`is_untouched()`), so an
  untouched island contributes an empty dictionary.
- **Loading RESTARTS the scene rather than patching the live one.** A world that has been played
  in carries chopped trees, placed buildings and a wandering population; unpicking all that
  correctly is far more fragile than building it once. `load_game` therefore does
  `change_scene_to_file` + two `await get_tree().process_frame` (one to swap, one for `_ready`),
  then applies. `apply_data()` is public so the regression can restore into a live world without
  a scene change.
- **`"version": 1` with a `_migrate()` hook that already exists.** A file from a *newer* version
  is refused outright rather than half-read — asserted.
- **Autosave is on the day roll**, to slot 0, which is also what the title screen's Continue
  reads. Slots 1 and 2 exist in `SaveManager`; the title screen deliberately only promises one.
- **⚠️ ALL AUDIO IS SYNTHESISED, by `tools/build_audio.gd`.** There is no audio in any of the
  asset packs and a "free" sound off the internet is a licence question nobody wants to answer
  later, so eleven sounds are generated from noise and sine waves. **No attribution, no licence.**
  - Written as **`.res` (binary AudioStreamWAV), NOT `.wav`** — `save_to_wav()` does not write
    loop points, so a looping ambience would need a hand-edited `.import` file to survive. A
    resource carries `loop_mode` with it and `load()`s with no import step at all.
  - **⚠️ The normalisation target IS the mix.** Before it existed, a measured footstep peaked at
    **0.97** and the pickup chime at **0.26** — every step drowned the reward sound. Peaks are now
    set deliberately per sound (step 0.32 · chop 0.85 · pickup 0.60 · craft 0.70 · place 0.75 ·
    ui 0.30 · eat 0.55 · fire 0.45 · amb 0.50/0.42 · music 0.55) and the regression asserts
    nothing clips and nothing came out silent.
  - Loops are **crossfaded into their own heads** (`_seamless`) so there is no seam; the buffer
    loses the folded-in tail, which is why the printed lengths are shorter than requested.
  - The theme is **pentatonic on purpose**: every note agrees with every other, so a randomised
    melody cannot come out wrong — exactly what an endlessly looping background needs.
- **Three buses** (`default_bus_layout.tres`): Master, Music, SFX. Nothing plays to Master
  directly. A slider at 0 **mutes the bus**, rather than sitting at -60 dB and still being audible.
- **⚠️ `PauseMenu` MUST be the FIRST child of `Main.tscn`.** `_unhandled_input` is delivered in
  reverse tree order, so the node listed *last* hears Esc *first* — and Esc already closes the
  bag, the craft menu and build mode. First in the tree means the pause menu only ever sees an Esc
  nothing else wanted. `layer = 8` keeps it drawn on top regardless. **The regression asserts
  this ordering**, because it looks purely cosmetic in the scene file and is not.
- **The pause menu pauses; the bag still does not.** It offers to throw the session away, and
  doing that while a deer wanders past is worse than a moment's stop. `process_mode = ALWAYS` on
  the menu and on `Audio`'s players, so both keep working through the pause.
- **⚠️ A Control only gets the viewport's rect when it is a ROOT control** — a child of the window
  or of a CanvasLayer. Parented to a Node2D it keeps size (0,0): the first `MainMenu` screenshot
  came out as a clipped panel jammed in the top-left. The engine gives the real main scene the
  first case; the shot tool had to be told to.
- **⚠️ Set `process_mode = ALWAYS` BEFORE anything pauses the tree**, not at the step that does
  it. A node only told to ignore the pause afterwards never runs again to be told — the shot run
  hung with its last two screenshots untaken.
- **⚠️ Six "leaked ObjectDB instances" at exit were live audio playbacks**, not a leak: a playback
  still running when the tree is torn down keeps its stream alive past cleanup. The suite now
  silences everything in `_finish()`. Six bogus leaks in the output is exactly how a real one
  would go unnoticed.
- **Polish, all of it wired to existing signals rather than new plumbing** (the second pass
  above adds the four items this first one missed):
  floating `+3 Berries` labels **parented to the player** so they travel with them (a screen-space
  label visibly slides off while you run) · footstep dust and sound **driven by distance, not a
  timer**, so they stay in step whether walking, running or slowed by cold · a horizontal shiver
  on the *sprite's* offset when cold (nudging the body would fight the physics and desync the
  shadow) · fireflies parented to the camera, faded in on `darkness()` **cubed** so they hold off
  until it is genuinely dark · a `Day 4` toast on `day_passed` · positional fire crackle that
  follows the *flame*, so an unlit fire is silent.
- **⚠️ Fireflies need an actual texture.** A CPUParticles2D with none draws a 1px point, which the
  night CanvasModulate then dims into nothing — the first night shot had no fireflies in it at
  all. They now carry an 8px radial `GradientTexture2D`. **Measured by frame diff** (fireflies
  shown vs hidden, same night frame, away from the fire so its glow is not the variable):
  **2379 of 230400 px differ, 1.03% of the screen, peak delta 229/255.** Worth doing — squinting
  at the screenshot, I was about to call them invisible a second time and they are not.
- **Regression is 188 checks.** Phase 10 adds 42, including a full save round-trip (bag, clock,
  warmth, fire fuel, a chopped tree, a placed building), the newer-format refusal, the bus
  wiring, a **PCM scan of every generated sound** for clipping and silence, and the pause-menu
  ordering invariant. Bump `EXPECTED_CHECKS` when adding more.
- **⚠️ Two of Phase 10's first three "failures" were the TEST being wrong, not the code:** the
  boulder `tree_node` drops stone into the bag, so chopping after setting the inventory up made
  the asserted counts wrong; and phase 8 already places a workbench, so "restored exactly once"
  had to become "loading does not *add* one". Measure the baseline, do not assume it.
- **`tools/phase10_shots.gd`** walks title → settings → day → pickup → toast → night → cold →
  save → trash → load → pause. The before/after-load pair is the proof: the session is
  deliberately trashed between them, so an unchanged shot would be a failure, not a pass.

### Phase 10 second pass — the four checklist items that were missed

Re-read `phase10_polish.md` line by line against what was actually built. Save/load, audio,
menus, settings, transitions, screen shake and the feedback bullet were all there. Four were not.

- **⚠️ The camera was not pixel-snapped, and the spec asks for it explicitly.** Measured: the view
  centre sat on a fractional coordinate on **99.6% of frames, worst remainder 0.5px**. With
  `snap_2d_transforms_to_pixel` on, every sprite then rounds its own screen position
  independently, so neighbouring tiles round different ways on different frames — the shimmer
  along tile seams. **Now 0.0% of frames, remainder 0.000px, asserted.**
  - **`player_camera.gd` is `top_level` and does its OWN smoothing.** It has to be: as an ordinary
    child it inherits the player's fractional position, and Godot's `position_smoothing` then
    lands the view on fractional coordinates too. Being top-level makes `position` world space,
    so the smoothed value can simply be rounded before it is written.
  - Easing is `1 - exp(-speed * delta)`, not a lerp by delta, so it is identical at any frame
    rate — which matters because headless runs `_process` uncapped.
  - **Shake is rounded too.** A half-pixel shake on a pixel-art game is not a subtler shake, it is
    the same shake plus the shimmer this was all meant to remove.
  - **⚠️ Two false starts worth not repeating.** First attempt corrected the fraction through
    `offset` — but `get_screen_center_position()` **does not include `offset` at all** (verified:
    setting offset to (100,50) moved the reported centre by (0,0)), so the correction was computed
    against a base it could never move and the figure stayed at 99.2%. Second attempt tried to
    verify `offset`'s sign by correlating two rendered frames, which failed because the water
    shader, the animals and the smoothing all move between frames as well. Driving the position
    directly is both simpler and actually measurable.
- **Fly-to-hotbar pickups.** The floating `+3 Berries` text was the *Feedback* bullet; the
  *Tweens* bullet asks for the item to fly into the bar, which is a different thing. The icon now
  arcs from the player into **the slot the item actually landed in** — looked up after the gain,
  not guessed — and the slot pops as it arrives. An item that stacked further back in the bag gets
  no flight at all, because an icon sailing into a corner would be a lie about where it went.
  The feed asks for the slot position **by group**, so it holds no path to the hotbar.
- **Campfire smoke**, drawn behind the flame (`z_index = -1`) so it rises from the back of the
  fire rather than in front of it, and thinned with the fuel: a roaring fire smokes, cold coals do
  not smoke at all.
- **Leaves on the wind**, parented under the camera like the fireflies, with the wind a slow
  38-second oscillation rather than a constant so the drift changes direction and the screen never
  looks like it is on rails. They fade back at night when the fireflies take over.
- **Measured by frame diff, the same way the fireflies were:** smoke **0.41% of the screen, peak
  delta 218/255**; leaves **0.65%, peak 227/255**. Both subtle on a still frame and both real,
  which is what an ambient effect should be.
- **⚠️ `amount_ratio` is a GPUParticles2D property and does not exist on CPUParticles2D.** Used it
  on both new emitters; it threw a runtime error every single frame. And **do not reach for
  `amount` instead** — assigning it reallocates the system and pops every live particle. Fade with
  `self_modulate.a`, which is free and continuous.
- **⚠️ A runtime SCRIPT ERROR does NOT fail the regression suite.** All 184 checks went green
  while those particle errors fired every frame, because the checks asserted the nodes existed,
  not that their scripts ran. Grep the run:

      godot --headless --path . res://tools/regression_check.tscn 2>&1 | tee /tmp/reg.log
      grep -c "SCRIPT ERROR" /tmp/reg.log   # must be 0

- **Spec deviations, flagged not improvised:** the spec says `GPUParticles2D`, but the project is
  on the **GL Compatibility** renderer and targets web, so everything stays `CPUParticles2D` —
  consistent with Phases 4, 5 and 9. The spec says "source cozy CC0 audio"; it is synthesised
  instead (see the Phase 10 notes), which needs no attribution at all. Animal population in the
  save is marked optional in the spec and is still skipped: the spawner refills to its caps on
  load, so storing counts would change nothing.

### Verifying the terrain look holds in ANY area, not just one spot

The owner approved a 6x-zoom shot of a grass/sand/water boundary as the standard. One spot
looking right is not the claim — **`tools/boundary_montage.gd`** samples real boundary cells from
all over the map, at that same 6x zoom, and tiles them into one contact sheet:

    xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/boundary_montage.tscn

- **12 samples, 3 of each boundary kind** (grass/sand, sand/water, woodland/grass, woodland/sand),
  forced at least `SPREAD` (14) tiles apart so no two come from the same neighbourhood.
- It clears the camera's world bounds first, or a coastal sample cannot be centred.
- **Checked this pass and all clean:** 12 boundaries + 4 biome interiors + 3 full-frame
  woodland/grass views. Every one matches the approved standard — curved boundaries, tufts on
  both sides, no hard edges.
- **⚠️ A montage crop is not proof on its own.** Three woodland/grass samples looked like they had
  straight vertical boundaries in the 320x180 montage cells; rendered full-frame they are plainly
  curved. Judge a suspicion at full size before acting on it.
- **Tuft coverage, measured:** sand 26.4%, grass 16.6%, woodland 15.9% of cells. Interiors were a
  worry after patches dropped from 25 to 4 — measured and rendered, they read fine.

### The hut interior uses 2 of the wall sheet's 14 usable cells

Audited for the first time (an earlier pass silently skipped it — the check was `async` and the
caller did not await it, so it never ran before `quit()`).

- `interior_tileset.tres` holds **exactly two tiles**: floor `(1,1)` and wall `(1,0)`. There is no
  terrain set and no autotiling at all, so it **cannot** pick a wrong-category tile — the room is
  a hand-painted wall ring.
- **Straight walls and 90 degree corners are CORRECT here.** The no-sharp-edge rule is for the
  *terrain* tileset; a room is architecture, and blob-ifying it would be absurd.
- **But the art is under-used:** `Wooden_House_Walls_Tilset.png` is 5x3 cells — **7 fully solid,
  7 partial, 1 blank** — and only 2 are registered. There are no distinct corner or side pieces,
  so the same horizontal plank texture runs round all four walls, and the doorway has no frame.
  That is a polish opportunity, not a defect.

### ⚠️ The hard green rectangles on the sand were the DETAIL layer

Found by looking at a boundary at 6x zoom instead of at play zoom. The terrain tiling was already
clean by then — this was scenery scattered on top of it.

- **`_add_detail()` selected cells by "all four extreme corners transparent", which does not mean
  loose.** A near-solid square with its corners clipped passes that test. Cell `(8,4)` is
  **240 of 256 px opaque**:

      ..############..
      ..############..
      ################
      ################      <- a solid green block
      ..############..
      ..############..

- **21 of the 25 registered "loose moss patches" were blocks like that**, 44-94% opaque, and they
  were being scattered onto the beach at `edge_detail_chance` 0.62. That is the source of the
  hard-edged rectangular patches on the sand — the same complaint from several rounds earlier,
  which was never the tiling at all.
- **Only 4 of 25 are genuine tufts** (23-29% opaque, widest row 8-11). The blocks start at 44% and
  a widest row of 12, so `MAX_PATCH_INK` (96) and `MAX_PATCH_RUN` (12) separate them cleanly.
- **⚠️ Nothing is scattered onto WATER any more.** "Sandy shoals spilling into the shallows" was
  the intent; measured, it was **270 hard-outlined beige lumps sitting on flat open sea**,
  detached from the beach, reading as litter. The shoreline gets its softness from the sand blob's
  own curved alpha edge, which no longer contains a single flat tile. `SRC_DETAIL_SAND` is still
  registered but deliberately unused.
- Both are asserted: *every scattered detail patch is a loose tuft, not a block*, and *no detail
  patch sits on open water*.
- **Lesson: judge scenery at 6x zoom, not at play zoom.** At play zoom a 16px green block on sand
  reads as "texture"; magnified it is obviously a rectangle.

### ⚠️ RULE: no sharp edge or hard corner may EVER be exposed

Standing rule for the terrain tileset. Every boundary the camera can see — grass/sand,
sand/water, grass/woodland — must resolve to a curved or blended piece. Never a straight
geometric line, never an unrounded 90 degree corner.

`tools/sharp_edge_audit.gd` counts violations, in three kinds, all read from the ARTWORK rather
than from the tileset's claims about itself:

| | kind | meaning |
|---|---|---|
| A | ruled line | a straight-edge tile whose inset never varies across its 16px |
| B | seam step | adjacent tiles whose shared boundary profiles disagree |
| C | hard corner | an exposed corner drawn as an unrounded right angle |

**Before: 32 violations of 1676 exposed boundary edges. After: 0.** Both asserted permanently.

| layer | boundary edges | A before → after | B before → after | C |
|-------|---------------:|------------------|------------------|---|
| Sand | 630 | 13 → **0** | 1 → **0** | 0 |
| Grass | 534 | 9 → **0** | 0 → 0 | 0 |
| Woodland | 512 | 9 → **0** | 0 → 0 | 0 |
| **total** | **1676** | **31 → 0** | **1 → 0** | **0** |

Row by row: 83 map rows carry an exposed boundary, **0 of them contain a sharp edge**.

#### ⚠️ The sheet holds TWO autotile sets, and only one tiles with itself

This is the real "pieces aren't clicking together" bug, and it is a **wrong-category** bug, not a
placement one. Placement was already provably correct — every cell's tile exactly matched the
signature its shape required.

- `Grass.png`'s **x >= 4 block is a second, narrow-strip autotile set.** Its pieces are cut 2px at
  *both* ends, and the 2x2 corner probe reads that rounding as "terrain absent" — so a **left-edge
  piece was labelled as a lone bottom-right corner**. Example, cell `(4,2)`, labelled signature 8:

      ..############..      <- 2px cut on the left, and a 2px nibble top-right
      ..#############.
      ..##############      <- rows 2-15: opaque all the way to x=15
      ...

  That is not a corner. It is a left edge. Registered alongside the main blob set, Godot picks
  between them at random, and a near-solid strip piece lands where a rounded curve belongs.
- **16 of 43 tiles per terrain were in the wrong category — 48 across the three land terrains.**
- **Caught by the one rule the corner probe cannot express:** the two corners along a side decide
  what that whole side must look like. Both set → the side must be essentially solid. Both clear →
  essentially empty. `build_tileset._wrong_category()` rejects anything that contradicts its own
  artwork.
- **⚠️ Do NOT try to re-label them instead.** Their shapes belong to a different set; correctly
  labelled they still would not tile with the main blob. Dropping is the fix.

#### Dead-flat straight edges are no longer registered at all

Every straight edge the pack ships is a flat 2px inset (measured, all eight, span 0), so a single
one anywhere is a ruled line exposed to the player. `FLAT_EDGE_WEIGHT` used to just make them
rarer (40% → 12%), which is not the same as never. They are now **rejected outright**, and the
generated wavy sheet supplies signatures 3/5/10/12 on its own.

- **Coverage works out exactly:** dropping 16 wrong-category + 4 dead-flat leaves 23 tiles
  covering 11 signatures; the wavy sheet supplies precisely the missing 4. **15/15 per terrain,
  all curved.** Completeness is now asserted **per TERRAIN across its sources**, not per sheet —
  the main sheet legitimately no longer carries those four.
- Both violation classes are now **structurally impossible rather than merely rare**: the offending
  tiles do not exist in the tileset, so no seed can select one.

### ⚠️ Corners and edges: the ACTUAL root cause (2x2 drawability)

This is the one that was really wrong, found by testing the tiling on **controlled shapes**
instead of on the noisy island.

- **The rule the art imposes:** the sheets are a 16-signature **corner-match blob set**. A tile
  shows terrain in whichever of its four corners are set, and a corner is set only when **all four
  cells meeting at that corner are the same terrain**. So a region is drawable only if
  **every cell of it belongs to at least one full 2x2 block of its own terrain**.
- **A cell in no 2x2 block has required signature `0000`, and there is no such tile** — `bits == 0`
  is a blank cell in the sheet. Godot does not fail on an unmatched signature, it **silently
  substitutes the nearest one**, which is a single rounded wedge. That is why a one-tile-wide
  strip rendered as a chain of disconnected nubs, a lone cell as one corner of a blob floating on
  its own, and a diagonal as a staircase of hard squares.
- **Measured on the shipped island before the fix:** **38 wrong tiles on Sand, 26 on Grass**, of
  which **3 lone cells and 40 one cell wide**. Woodland was clean, but only by luck —
  `min_grove_cells` filters region *area*, and a 10-cell grove can be a 1x10 strip.
- **Fix: `IslandGenerator._open_2x2()`** — morphological opening with a 2x2 structuring element,
  run to a fixed point, applied to each of the three nested masks in order: **land** (failures
  become water), **inland = grass∪forest** (failures become sand), **forest** (failures become
  grass). It must iterate: clearing a cell can leave its neighbour in no 2x2 block either, so one
  pass fixes a strip's middle and leaves fresh nubs at its ends.
- **Ordering is load-bearing.** The land mask is opened **before** the beach is measured, or the
  beach ring would be computed against a coastline that is about to change. The woodland mask is
  **re-masked against the opened inland mask** before being opened itself.
- **Cost: 29 land cells of 3889 (0.75%) and 14 grass cells.** The island silhouette is unchanged
  to the eye; what disappears is one-tile spits, which looked like errors anyway.
- **Verified:** 0 wrong tiles and 0 undrawable cells on all three layers, asserted permanently
  (6 checks). And `tools/terrain_seed_sweep.gd` runs **25 different seeds** — 0 undrawable cells —
  so it is a property of the generator, not of one island.
- **`tools/tile_shape_shots.gd`** renders the proof: blob / strip / lone / diagonal, raw on top
  and opened underneath. The blob is identical in both rows; the other three vanish, because the
  tileset genuinely cannot draw them.

#### ⚠️ Why the earlier "fill tiles at boundaries" investigation found nothing

It asked **the wrong question**, and got a correct answer to it. "Is a FILL tile sitting at a
boundary" is structurally impossible in corner-match mode and always returns 0 — a foreign
neighbour shares two of a cell's corners, so those bits cannot be set. The right question is
**"does the tile Godot placed exactly match the signature the region requires?"**, because an
unmatchable signature is substituted, not rejected. `_check_drawable()` in the regression asks
that one now. Keep asking it.

#### ⚠️ A parse error in the regression HANGS it, it does not fail it

A duplicate local (`seen`) failed the script load, the scene never reached `quit()`, and the run
sat there until the shell timeout killed it at 550s. An empty log plus a timeout means **look for
a parse error first**, not a slow check.

### ⚠️ Fill tiles at boundaries: checked, and it is NOT what happens

A review suspected the generator was placing FILL (all-corners) tiles at boundary positions
because the peering bits were mis-wired. Scanned the whole island: **0 fill tiles at a boundary**
on all three layers. It is structurally impossible in corner-match mode — a foreign neighbour
shares two of a cell's corners, so those bits cannot be set and a fill tile is unselectable there.

**⚠️ True, but it was the wrong question** — see the 2x2 drawability section above, which is where
the real corner/edge bug was. Both checks are in the regression; the drawability one is the one
that catches things.

- **What WAS still making straight runs look ruled:** Godot picks uniformly among equally-good
  matches, and a straight-edge position had **2 flat originals + 3 generated wavy** candidates —
  so **40% of straight edges came out flat**, every one of them a correct edge tile.
- **`FLAT_EDGE_WEIGHT` (0.2)** sets `TileData.probability` on the pack's flat straight edges only.
  Flat share drops from **40% to ~12%**, which keeps a few genuinely straight stretches without
  the coast looking drawn with a ruler. Asserted at under 25%.
- Tile census per terrain source: **13 fill · 10 two-corner · 20 corner/inner**, plus 12 wavy
  straight edges in the generated sheet.

### Biome SHAPES (the other half of the blocky-edge problem)

Wavy edge tiles fixed how a boundary is *drawn*. These fix what shape the regions are in the
first place — a tile can only describe a curve if the region has one to describe.

- **⚠️ Sand is DISTANCE TO WATER now, not an elevation band.** As a band (0.30-0.38) it appeared
  wherever terrain happened to sit in that range, so a flat inland plateau became a broad beige
  patch in the middle of the island with nothing coastal about it. A BFS out from the water
  (`beach_width`, default 2) guarantees beaches ring the coast and cannot appear inland.
  `sand_level` is gone; `land_level` is now the single water/land threshold, at the same 0.30 the
  old `sand_level` used — so the island silhouette and the 3889 land cells are unchanged.
- **⚠️ `cover_frequency` was 0.09 — far too high.** That is a grove about 11 tiles across, and
  thresholded it left speckle: lone cells and one-tile spits. **No autotile set can draw those
  as anything but a hard rectangle**, which is exactly what read as "two grass shades in blocky
  patches". Now **0.026**, so groves are large.
- **`cover_smoothing` (3 majority-filter passes)** over the woodland mask removes what noise
  leaves behind. Five of eight neighbours agreeing flips a cell; fewer leaves it. Large smooth
  regions are the precondition for the edge tiles mattering at all.
- **`min_grove_cells` (10)** dissolves woodland regions below that size back into grass. Smoothing
  alone still left lone cells, and a one-tile grove is exactly the hard square all of this was
  meant to stop — there is no edge for a tile to draw, only corners meeting corners.
- **⚠️ The mask must know about the BEACH before it is cleaned up.** The beach ring cuts through
  the woodland mask, so a filter run on the raw mask saw **2 big groves** where the finished map
  had **13 fragments**, and dutifully dropped none of the specks the slicing created. The mask is
  built over eligible cells only (land, past the beach) and re-masked after every smoothing pass.
- The grass-woodland boundary was already on the terrain/bitmask system and already had the wavy
  variants — it looked blocky purely because the *regions* were. Nothing about the tiling changed.
- **Measured on the shipped island:** sand 861 cells, **every one within 2 tiles of water**
  (worst case == `beach_width`); woodland **8 groves, 0 under 10 cells**, spanning 7x8 up to
  35x46 tiles. Both are asserted in the regression, so neither can silently regress.

### Generated wavy edge tiles (closes the blocky-edge thread)

- **⚠️ Every straight edge the pack ships is a FLAT 2px inset.** Measured on all eight, span 0.
  So a run of grass against sand was a ruled line *by construction* — the shape simply is not in
  the art, and no autotile wiring changes that. (An earlier note measured left/right from the
  wrong side; the verdict held, the numbers did not. Grass-on-the-right means the gap is on the
  LEFT.)
- **`build_terrain_atlas.gd` now generates 12 wavy variants** — 4 directions x 3 bulge profiles —
  from the sheet's own palette (`grass_edges.png`, then darkened and re-hued to
  `wood_edges.png` / `sand_edges.png` by the same two transforms as the main sheets).
- **Both ends are pinned at the pack's own depth of 2**, bulging to 8 in the middle. That is what
  lets a generated tile abut the pack's flat edges and hand-drawn corners with no step — any
  variant can follow any other.
- They are registered as **extra sources (8/9/10) carrying the same corner bits**, so Godot mixes
  them with the flat originals at random. `_add_terrain` takes `require_complete := false` for
  these: they only cover the 4 straight-edge signatures and top the main sources up.
- **⚠️ A PNG written this run is not importable yet** — `load()` on it returns null until Godot
  reimports. The edge sheet is kept in memory and handed straight to the darken/re-hue steps.
- **⚠️ Do not assume a cell's source id.** The regression's edge check looked coords up in
  `SRC_SAND` and crashed once wavy tiles appeared, because those live in their own atlas. Read
  `get_cell_source_id(cell)` per cell.
- Measured result: **161 of 652** shoreline edge tiles are the generated variants, asserted.

### Terrain + UI corrections (owner review, post-Phase-9)

Five things were called out on review. All five were real; two of my earlier claims were wrong.

- **⚠️ "13 grass variants" was true and meaningless.** 8 of the 13 solid cells differ from the
  plain one by only **1-6% of pixels**; just 4 carry real detail. The autotiler was mostly
  choosing between identical tiles. **Fix:** a `Detail` TileMapLayer scattering the sheet's 25
  **loose moss patches** (the `0000`-corner cells, drawn on transparency) across grass and
  woodland at `detail_chance`.
- **⚠️ "Edges curve" was simply wrong.** Measured: a straight-edge grass tile's transparent run is
  **a flat 2px on every row — the curve spans 0px**. Only the CORNER tiles round off. The pack
  cannot draw a curved straight edge, full stop. **Fix:** the same loose patches are scattered at
  `edge_detail_chance` (0.62) on the far side of each boundary — green spilling onto sand, sandy
  shoals spilling into the shallows — so the eye reads a ragged edge instead of a staircase.
  This is decoration over a square grid, not a genuinely curved transition; it is as close as
  this art gets.
- **Blossom trees are out of the scatter.** They read pink/magenta against this palette and
  looked like an error. One entry removed from `World.tscn`'s `harvestables`; `tree_blossom.tres`
  is still there if the palette ever suits it.
- **The HUD and hotbar now sit in themed `PanelContainer`s.** They were bare labels and loose
  slots over the world — the theme was working, but nothing had been *put inside a panel*, which
  is why the GUI still looked unthemed. `hud.gd` and `hotbar.gd` node paths moved under `Frame`.
- **⚠️ A REAL BUG surfaced by tightening a weak check.** The wander test accepted **>1px after a
  fixed wait**, which a merely *settling* animal passes. At a real 12px threshold, animals turned
  out to get **wedged against trees forever** — velocity at full speed, position frozen, target
  reported perfectly reachable. **The navigation mesh knows about water but not about trees,
  rocks or buildings**, which are plain StaticBody2D colliders it never saw. `animal.gd` now
  watches for pushing-without-progress (`STUCK_SECONDS`) and re-targets. The proper fix is
  carving scenery out of the mesh — `World._occupied` already holds the data.
- **The wander check polls instead of sleeping.** First attempt accumulated `delta` inside a
  `wait` window that short-circuits before the poll runs, so a 25s deadline took **2000 real
  seconds** and the suite timed out. Poll every frame.

### Terrain rebuild (post-Phase-9)

- **The island is LAYERED now, not one flat grid of terrain rows.** Sea under every cell, then
  `Sand`, `Grass`, `Woodland` TileMapLayers, each autotiled against emptiness. The Sprout Lands
  edge pieces are drawn on transparency, so a grass blob laid over sand *curves into* it. The old
  `Ground` layer is gone; `world.ground_layer` now points at **`Sand`**, which covers every land
  cell and therefore carries the navigation mesh and answers "is this dry land".
- **⚠️ Biome is no longer recoverable from the tilemap** — the layers encode SHAPE, not terrain.
  `World.terrain_at(cell)` reads the stored generator grid. Anything that used to infer terrain
  from `get_cell_atlas_coords().y` is wrong now.
- **⚠️ The corner bits are MEASURED FROM THE ART, not typed in.** `build_tileset.gd` probes each
  16px cell at its four extreme **2x2** corners: opaque = that corner is this terrain. Both
  `Grass.png` and `Tilled_Dirt.png` yield a complete 16/16 corner set that way. **A 3px probe does
  not work** — the diamond notches that form the inner corners sit exactly on the cell junction,
  so a wider probe straddles them and reports a solid corner. That one pixel of slop is the
  difference between 10/16 and 16/16 signatures.
- **Texture variety is free.** Every fully-solid cell is registered as its own tile with identical
  corner bits, so Godot picks at random among equal matches: the grass interior is drawn from
  **13** different cells, sand from 13, rather than one repeated tile.
- **⚠️ The beach is the GRASS blob re-hued, not Tilled_Dirt.** Tilled_Dirt is ploughed-field art —
  its edge pieces are nearly square, because the edge of a ploughed field is meant to be straight.
  Used as a beach it produced the one genuinely blocky boundary on the island. `build_terrain_atlas.gd`
  luminance-remaps the grass blob onto sand's hue (`sand_blob.png`). Sampling sand's own ramp
  directly does NOT work: it spans luminance 190-219 against grass's 140-228, and flattening to
  that erases the dark outline that makes the edge read.
- **⚠️ There is ONE sea colour, deliberately.** The pack has no deep-to-shallow transition art, so
  two flat water tiles met at a hard rectangular step — the most obvious artefact on the first
  rebuild. The generator still classifies `DEEP_WATER`; nothing draws it differently.
- **Two water sources, same art:** source 0 carries collision (open sea), source 1 does not and is
  painted UNDER the land. Without the collision-free twin the player is walled in on dry ground.
- **The sea shimmers by shader, not by frames.** The sheet's four animation frames differ by only
  **2-4% of their pixels**, which is why the sea read as static; they still cycle, and
  `assets/shaders/water_shimmer.gdshader` adds movement on top. It modulates COLOUR only and reads
  the texture at its true UV — nudging UV on a TileMapLayer would drag neighbouring tiles' pixels
  in across the atlas and break seams. Fully transparent pixels are skipped so the shoreline's
  soft alpha edge survives. Measured: **54.6% of sea pixels move, median delta 2/255, peak 16**.
- **⚠️ Every tree and bush PNG on disk is ALREADY in the scatter** — all 22 trees, all 6 bushes.
  There is no unused nature art to add variety from. Rock clusters, gem bushes, stumps and ruins
  exist only in pasted preview images that never became files.
- `tools/terrain_shots.gd` shoots the island from above and at each biome boundary. Blocky edges
  are invisible at play zoom and obvious from above — judge terrain there, not in a gameplay shot.
- **Regression is 131 checks**, and now asserts the things that actually matter: sand covers
  exactly the land, no land cell sits on solid water, every terrain has all 15 corner cases plus
  interior variety, and **the shoreline uses 652 edge tiles rather than squares**.

### UI theme (post-Phase-9 fix)

- **The RPG UI pack was never actually in the repo**, so Phase 6's "theming" was plain default
  Godot styling the whole time. `assets/ui/source/` now holds the four **neutral** sheets only —
  `Main_tiles`, `Buttons`, `Inventory`, `Settings`. The shop, equipment doll, level select,
  win/lose star screens, circle menu and the pack's own combat icons are **deliberately not
  copied in at all**; item icons stay in `assets/icons/`.
- **⚠️ A theme alone changes nothing if the scenes override it.** Every UI scene carried its own
  `StyleBoxFlat` (`theme_override_styles/panel`), and a local override always beats the project
  theme — that is the real reason the old styling never took. Those overrides are gone.
- **`tools/build_ui_atlas.gd`** cuts 8 pieces out of the pack and **measures each one's border
  inset**, which is where the nine-slice margins come from. **⚠️ The obvious button rows are
  useless — "RESTART" / "RESUME" / "SAVE" are baked into the pixels.** The blank ones are in the
  top-left block of `Buttons.png`. The four shades are two greens x (with / without a brown drop
  shadow), so: `normal` = mid+shadow, `hover` = light+shadow, `pressed` = mid with the shadow
  removed, which is what reads as pushed in.
- **Panel margins are 6, not the measured 4** — the corner radius is bigger than the straight
  border, and slicing at 4 drags the curve into a smear.
- **⚠️ The pack's slot swatches are flat single colours** (brown `#9d775d`, tan `#cda677`) — there
  is no bordered slot sprite to nine-slice. The grid look comes from the gaps between slots.
- **`tools/build_ui_theme.gd`** generates `resources/ui_theme.tres` and asserts every textured
  stylebox survives the round-trip. Registered as `gui/theme/custom` in `project.godot`, so new
  UI scenes inherit it with no wiring.
- **`Label` is deliberately NOT themed globally.** HUD labels sit over the world and must stay
  light with an outline; only text on parchment goes dark, via the `PanelText` / `PanelTextDim`
  type variations. Other variations: `SlotPanel` (inventory slots), `RecipeRow` (craft rows,
  inset tan so parchment does not stack on parchment).
- **`tools/ui_shots.gd`** shoots the HUD, bag and craft menu — a theme that loads is not the same
  as a theme that renders.

### Phase 9 notes

- **Animal sheets are 32x32 cells, 4 rows, columns = frames** — verified on every sheet.
  **⚠️ The ROW ORDER IS NOT THE SAME FOR EVERY ANIMAL.** Hare and deer are
  `down, up, left, right`; the **black grouse has its two side rows swapped**
  (`down, up, right, left`). Found by locating the eye pixel inside each side row's alpha
  bounds, not by assuming. Row order is therefore a field per animal in
  `tools/build_animal_frames.gd`, never a constant. (Note this is also *not* the player's order,
  which is `down, left, right, up`.)
- **Feet offsets, measured across every frame of every sheet:** hare **-11**, deer **-11**,
  grouse **-9**. Taken from the idle/walk frames only — the death frames sprawl 1-2px lower, and
  anchoring to those floats the animal off the ground while it is standing.
- **`tools/build_animal_frames.gd`** generates all three `SpriteFrames` (60 animations, 312 atlas
  regions) and asserts each one round-trips through `ResourceSaver`. Regenerate rather than
  hand-edit, exactly like the player's frames.
- **Navigation is on the TILESET, not a hand-placed region.** `tools/build_tileset.gd` now adds a
  navigation layer and gives every **land** tile a full-cell nav polygon; `TileMapLayer` bakes
  those into navigation regions itself. Because water has none, **an animal's NavigationAgent2D
  physically cannot path into the sea** — which is the shoreline wall-hugging the spec asks us to
  avoid. Note `make_polygons_from_outlines()` is deprecated in 4.7: set `vertices` and
  `add_polygon()` directly.
- **`AnimalData` is the whole personality.** Speeds, detection radius, wander range, rest times,
  hits, drops, spawn terrains and population are all data, so adding a species is a `.tres` plus a
  SpriteFrames. `animal.gd` never learns what a hare is.
- **`HarvestDrop` is now shared by harvestables AND animals** rather than growing a near-identical
  `AnimalDrop`. It gained **`chance`** (default 1.0, so every pre-Phase-9 `.tres` behaves exactly
  as before) — that is what makes a deer's antlers uncommon. Both callers skip a roll of 0.
- **State machine: REST → WANDER → FLEE.** There is deliberately **no HURT state** — being hit
  also startles, so a HURT state was stomped by the movement animation the very next frame. It is
  a 0.25s timer that suppresses `_animate()` instead. Wandering is around **where the animal
  spawned**, not where it is now, so a long chase does not leave it homeless.
- **No aggression anywhere** (spec, and CLAUDE.md rule 6). Boar and fox are in the pack and
  deliberately unused — the boar has an attack animation and that is a conversation, not a
  default. The regression asserts `Animal` has no `attack` method.
- **Hunting reuses the harvest input and the group-call swing** — E in reach, `call_group("player",
  "swing", ...)`, so animals hold no player reference either. A carcass drops its loot, stops
  colliding immediately, lingers 0.9s, then fades and frees itself.
- **The spawner tops up slowly** (`respawn_seconds` 24) and only **out of sight of the player**
  (`respawn_clearance` 200px), so nothing pops into existence in front of you. Caps are per
  species: hare 12, deer 8, grouse 10 = **30 across the island**. With a 320x180 viewport over
  ~1.1M px² of land that is roughly **1-2 animals on screen at a time** — wildlife, not a petting
  zoo. A carcass stops counting toward the cap the moment it dies, not when the node frees.
- **New branch of the tree, all data:** `venison` · `antler` · `raw_poultry` drop from the
  animals; **campfire:** `venison -> roast_venison`, `raw_poultry -> roast_poultry`;
  **workbench:** `antler + plank x2 + rope -> hunting_knife`. Cooked dishes carry `hunger` like
  `cooked_meat` **plus** a little `warmth`, which is the stat that actually exists today.
  New icon cells: `venison` meat (6,2) · `antler` meat (6,5) · `raw_poultry` meat (3,1) ·
  `roast_venison` food (1,5) · `roast_poultry` food (8,9) · `hunting_knife` tools (0,2).
  **Note the two icon atlases have different cell sizes:** `items_raw_meat_bones` is **36px, 8x6**;
  `items_food` / `items_tools_ores` are **32px, 10x10**.
- **⚠️ Two Godot gotchas found the hard way:**
  1. **Headless runs `_process` uncapped, so counting frames is not counting time.** 60 frames
     measured a few milliseconds and every timed check failed for no reason. All of Phase 9's
     regression waits are in **seconds**, accumulated from `delta`.
  2. **A freed Node leaves a GDScript variable `null`, not merely invalid.** A check written as
     `not is_instance_valid(x)` never ran because an earlier `x == null` guard caught it first.
- **Regression suite is 118 checks** and now has a **multi-frame tail**: Phase 9's behaviour
  (wandering, fleeing, hunting, respawn) only exists over time, so it runs as a short script of
  steps from `_process` after the single-frame phases. Bump `EXPECTED_CHECKS` when adding checks.
- **`tools/phase9_shots.gd`** is the visual walkthrough. It re-aims the camera **immediately
  before each capture** — a wandering animal drifts out of frame during a wait — and refuses to
  park the player on water, since teleporting ignores collision and a shot of the player stood in
  the sea looks broken even though it is unreachable in play.
- **⚠️ Still swinging a sword at the wildlife.** Same placeholder flagged in Phase 5; it reads
  even worse now that it is pointed at a deer. One SpriteFrames swap when axe art turns up.

### Phase 8 notes

- **⚠️ Spec conflict, flagged not improvised:** the phase spec says interiors are built "from the
  dungeon-pack walls/floors", but that pack is restricted to **fire, doors and chests only**
  (your call, Phase 3). Interiors therefore use Sprout Lands'
  `Wooden_House_Walls_Tilset.png` instead — floor `(1,1)` cream brick, wall `(1,0)` planks, built
  by `tools/build_interior_tileset.gd`. It matches the rest of the game's art better anyway.
- **`Room` is the new base class** (`scripts/world/room.gd`). Anywhere the player can stand is a
  Room and answers four questions: where to arrive (`entry_position`), which node to Y-sort them
  into (`sort_layer`), how to clamp the camera (`camera_bounds`), and `on_entered`/`on_exited`.
  `World` and `Interior` both extend it, so the manager never special-cases the island.
- **`RoomManager` owns the player, not the world.** `Main.tscn` is now
  `Main > Rooms(RoomManager) > {World, Player}` — **the Player instance moved out of
  `World.tscn`**; the manager reparents it into the current room's Y-sort layer. Rooms are
  **cached and hidden, never freed**: regenerating the island on every doorway would be slow and
  would undo every tree you chopped.
- **⚠️ Hiding a room does NOT disable its collision.** The first build put interiors on top of
  the island, and the player stood in a hut was being shoved around by the *ocean's* collider.
  Interiors are now parked in their own world slot (`SLOT_ORIGIN` (-20000,-20000), `SLOT_PITCH`
  2048) so inactive rooms are spatially harmless. Bonus: the island's `SkyTint` CanvasModulate is
  a child of `World`, so hiding the island also lifts the night tint — interiors are lit.
- **Doors defer their group call.** `body_entered` fires mid physics-flush; instancing an interior
  there means adding Area2Ds during the flush, which the physics server refuses
  (`area_set_shape_disabled` … "while flushing queries") and leaves the new door's shape broken —
  so the exit you walked in by never fires again. `call_group_flags(GROUP_CALL_DEFERRED, …)`.
- **The door cooldown holds, it does not drop.** 0.6s after arriving, doors are ignored so you
  cannot bounce straight back. Originally that *discarded* the trigger, so walking straight onto
  the far door did nothing until you stepped off and back on. It now parks the door in `_pending`
  and fires it when the cooldown ends, but only if you are genuinely still stood in it.
- **Camera bounds are pulled, not pushed.** `World._ready()` runs before the player's camera
  exists, so the old `call_group(PlayerCamera.GROUP, "set_world_bounds", …)` inside `build()`
  found nothing. Rooms now *report* `camera_bounds()` and the manager applies it on activation.
  An empty `Rect2` means unlimited.
- **Build mode (B) lives under the Player** and never touches the world directly — it asks the
  current Room `can_build()` / `build_at()`, so an interior could allow building by overriding
  two methods. The ghost wears the placed scene's **own** `$Sprite` texture, so there is no
  preview art to keep in sync. Green = valid, red = blocked; clamped to 6 tiles' reach; the item
  is spent **only after** the world accepts the building.
- **Placement is a data question.** `ItemData` gained `placed_scene` + `placed_footprint`;
  `is_placeable()` is just "has a scene". Four buildables ship: `campfire_kit`, `workbench`,
  `fence` (all 1x1) and `hut_kit` (3x3). Multi-tile footprints anchor on their **bottom centre**
  (`World.footprint_anchor`) so a hut sits on the tiles the ghost showed.
- **`World._occupied` is the one source of truth for free ground.** Harvestables, the seeded
  campfire and every placed building mark their cells; `can_build` also requires a painted ground
  cell, which rules out the sea and the map edge in one test.
- **Interiors are painted, not hand-authored.** `room_size` (default **14x10**) is an export;
  `interior.gd` paints the wall ring, leaves a gap at the bottom-centre door cell, and derives
  `$Entry` and `$ExitDoor` from it — so resizing a room cannot leave the door in a wall.
  A 10x7 room (8x5 of walkable floor) behind a 3x3 hut is the "bigger on the inside" conceit.
  **Sizing was tuned by eye, not guessed: 24x16 and then 14x10 both read as a hall — owner's call,
  twice. Err small.** The trick is that it only has to beat the footprint outside, not fill the
  screen. A `Backdrop` ColorRect sized in code covers the gap around a room
  smaller than the viewport, which otherwise showed the engine's clear colour.
- **Shelter reuses the campfire's counted heat hook** — `Interior.on_entered()` calls
  `GameState.add_heat_source()`. The warmth system still has no idea what a building is.
- **New keys:** **B** toggles build mode, **left-click / E** places, Esc cancels.
- **Regression suite was 78 checks at this phase** and guards against its own truncation: a runtime error
  used to abort a phase and still print "ALL GREEN", so `EXPECTED_CHECKS` is asserted at the end.
  Bump it when you add checks.
- **`tools/phase8_shots.gd`** is a repeatable visual walkthrough — it drives build mode through
  the real input path, places a hut, steps inside and back out, saving a shot at each beat. Needs
  a display: `xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/phase8_shots.tscn`.
- **⚠️ Workbench/fence art is borrowed.** The workbench is Sprout Lands' dresser
  (`sprout_furniture` `Rect2(48,32,16,16)`) and the hut is `Free_Chicken_House`. Both are one
  `region`/`texture` line away from better art.

### Phase 7 notes

- **Five autoloads now**, in order: `DayNight`, `GameState`, `ItemDB`, `Inventory`, `Crafting`.
- **The recipe tree is emergent, not encoded.** `RecipeData` + `RecipeIngredient` `.tres` files in
  `resources/recipes/`; a recipe whose ingredient is another recipe's result is simply deeper, and
  nothing in `crafting.gd` knows the shape. Current tree:
  `wood -> plank x2` · `fibre x2 -> rope` · `plank+fibre -> torch x2` ·
  `wood x3 + stone -> campfire_kit` · `plank x4 + stone x2 -> workbench` ·
  `bone + plank -> bone_tool` · **campfire:** `raw_meat -> cooked_meat`,
  `berries + fibre -> warmth_tonic` · **workbench:** `plank x2 + rope + stone x3 -> stone_axe`.
- **`craft()` is transactional.** If the result cannot fit once the ingredients are gone, every
  ingredient is put back and nothing is crafted. Crafting is destructive, so "half consumed and
  the output lost" has to be impossible.
- **Stations use counted registration**, the same proven shape as heat sources:
  `crafting_station.gd` is an `Area2D` you drop under any world object with a `station_id`, and
  `Crafting.add_station()` / `remove_station()` tally it. Two overlapping stations of the same
  kind cannot cancel each other out, and `_exit_tree` hands the registration back.
- **The campfire is a `campfire` station only while lit** — it drives `$Station.active` from
  `lit_changed`, so letting the fire die takes cooking with it.
- **⚠️ Workbench recipes are unreachable in actual play until Phase 8.** Crafting a workbench
  gives a *workbench item*; there is nothing to place it with yet, so `stone_axe` can only be
  reached through the API (the regression suite does exactly that). This is what the phase spec
  asked for — placement is Phase 8.
- **Consumables read their own stats.** `GameState.consume(id)` applies `warmth` from
  `ItemData.stats` and returns false if the item does nothing, so the caller knows not to spend
  it. The player presses **F** to use the selected hotbar item. Nothing in that path knows what a
  warmth tonic is. Hunger is read for too, ready for when a hunger stat exists.
- **The craft menu lists EVERY unlocked recipe**, greying what you cannot make and saying why
  ("needs workbench") — a visible locked branch is how the player learns the tree exists. Rows are
  built from whatever `Crafting` loaded, so a new `.tres` appears with no UI change.
- **Icon tool now handles all four sheets** and keys out **multiple background colours** — the
  potions and meat sheets put each icon on its own backing tile *in a different colour from the
  sheet border*, so keying only the corner left every icon on a brown square. Their layout also
  differs: 2x upscale, 8x6 grid, pitch (80,72), 70px art halved with Lanczos into 36px cells.
  New cells in use: `plank` tools (3,3) · `rope` tools (1,3) · `torch` tools (9,3) ·
  `campfire_kit` tools (4,3) · `workbench` tools (7,3) · `stone_axe` tools (0,0) ·
  `bone_tool` tools (6,2) · `raw_meat` meat (0,0) · `bone` meat (7,5) ·
  `cooked_meat` food (2,5) · `warmth_tonic` potions (0,3).
  `rope` borrows a bundle-of-sticks icon — the packs have no actual rope. Swap it when better art
  turns up; it is one `region` line in `resources/items/rope.tres`.
- **Keys:** C opens crafting, F uses the selected hotbar item (Tab/I bag, 1-8 hotbar, E interact).
  Phase 8 adds **B** for build mode.

### Phase 6 notes

- **Four autoloads now**, in this order: `DayNight`, `GameState`, **`ItemDB`**, **`Inventory`**.
  ItemDB must precede Inventory — stack limits are looked up through it.
- **`ItemData` is pure data.** Adding an item is a new `.tres` in `resources/items/` and nothing
  else; `ItemDB` scans that folder at boot and everything else passes string ids around. It
  strips `.remap` so exported builds still load, rejects blank/duplicate ids, and returns
  `max_stack = 1` for an unknown id so a typo cannot create an infinite stack.
- **`stats` is a free-form dictionary** on `ItemData`, so a new kind of item never needs a new
  field. The campfire reads `wood`'s `"fuel"` stat instead of its own constant — better firewood
  is a new `.tres`, not a code change.
- **`Inventory` semantics, relied on by Phase 7:**
  `add_item()` tops up existing stacks *before* opening a new slot and **returns the leftover**
  that would not fit; `remove_item()` is **all-or-nothing** (a recipe can never half-consume its
  ingredients) and drains the smallest stacks first so the bag tidies itself.
  **The hotbar IS the first 8 inventory slots** — there is no second store to keep in sync.
- **⚠️ The CraftPix icon sheets in `assets/icons/` are marketing previews, not game art.** They
  are **3x nearest upscales** (verified: integer-scale error 0.016 at scale 3 vs 0.071/0.116
  either side), sit on an **opaque brown background**, and have category labels ("fruits",
  "vegetables"…) baked into the left margin. `tools/build_icon_atlas.gd` downscales to native
  600x400, keys the background out, skips the label margin and re-centres each icon from its own
  alpha bounds into `assets/icons/items_*.png` — a 10x10 grid of 32px transparent cells.
  Item `.tres` files reference those with `AtlasTexture`. Cells in use:
  | item | sheet | cell |
  |------|-------|------|
  | wood | `items_tools_ores` | (0,3) log |
  | stone | `items_tools_ores` | (1,1) rock cluster |
  | fibre | `items_food` | (8,3) wheat |
  | fruit | `items_food` | (0,0) apple |
  | berries | `items_food` | (2,1) berry cluster |
  Only `icons_food` and `icons_tools_ores` are cleaned so far. **`icons_raw_meat_bones` has a
  different layout** — no background gutters were detected, so it needs its own grid worked out
  before Phase 9 uses it for animal drops.
- **`GameState` no longer holds items at all.** The `_materials` placeholder, `wood`, and all the
  add/spend helpers are gone; it is warmth and heat sources only. Phase 4 and 5 were retro-fitted.
- **The bag does not pause the game** — stopping the world to look in a bag is the opposite of
  cozy. Tab or I toggles it, Esc closes it, 1-8 select hotbar slots.
- Hotbar and bag build their slots from `Inventory.HOTBAR_SIZE` / `SLOT_COUNT`, so resizing
  either is a one-line constant change.

### Regression suite — run this after ANY change

    godot --headless --path . res://tools/regression_check.tscn

188 checks across every phase built so far; exits non-zero on failure. It exists because a
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
- **Trees use per-node sprite variants.** `HarvestableData.sprite_variants` /
  `harvested_variants` hold several looks for one kind; each spawned node picks one, seeded from
  **its own position** (`_visual_rng`), so a given island always looks the same while drops stay
  genuinely random. 18 tree sprites are in play — the pack ships each species at three sizes,
  which also gives a natural spread of mature trees and saplings (18-41px at `sprite_scale` 0.55).
- **Seven harvestable kinds**, weighted by terrain so the island reads naturally:
  | kind | sprites | terrains |
  |------|---------|----------|
  | `tree_palm` | Palm_tree1/2 x 3 sizes | sand, grass — hugs the shore |
  | `tree_leafy` | Tree1-3, Moss_tree1-3 | woodland, grass — inland |
  | `tree_fruit` | Fruit_tree1-3 | grass, woodland |
  | `tree_blossom` | Flower_tree1-3 | grass |
  | `bush_berry` / `bush_blue` | 3 growth stages each | grass, woodland |
  | `rock` | Sprout Lands boulder | sand, grass, woodland |
  Autumn, snow and christmas trees are in the pack but deliberately unused — wrong for a tropical
  island. Adding them is a `sprite_variants` edit.
- **Boulders are the stone source** (`resources/harvestables/rock.tres`, "Boulder"), scattered on
  sand, grass and woodland at a 0.02 chance — about 90 across the island. There is no rock
  terrain to mine.
- **Density is ~520 nodes, roughly 1 per 7 land tiles.** The first pass at 824 was a wall of
  foliage with the player invisible inside it; with the variety in place 520 reads as woodland
  with real clearings rather than a wall.
- **Materials moved to `Inventory` in Phase 6.** Drops call `Inventory.add_item()`; the
  placeholder dictionary that lived on `GameState` is gone.

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
