# Cozy Island Survival — Claude Code Project Kit

This repo is a **spec-first setup** for building a cozy 2.5D pixel-art island survival game in
Godot 4 with Claude Code. The docs do the heavy lifting: Claude reads `CLAUDE.md` every session,
and you feed it one phase spec at a time.

## First-time setup

1. **Create the Godot project.** Open Godot 4.x → New Project → point it at this folder (so
   `project.godot` sits next to `CLAUDE.md`). Godot will add `project.godot` and `.godot/`.
2. **Unpack the art.** Put the 5 CraftPix `.zip` files in `raw_assets/` and run:
   ```
   bash setup_assets.sh
   ```
   This extracts and copies the right PNGs into `assets/…`. (Or do it by hand using `docs/ASSETS.md`.)
   Also drop the 4 icon-sheet images into `assets/icons/`.
3. **Open Claude Code** in this folder:
   ```
   claude
   ```
   It auto-reads `CLAUDE.md`.

## How to run each phase

Paste this to Claude Code, changing the number each time:

> Read `docs/phases/phase00_setup.md` in full, then follow it. Before writing anything, list the
> exact files you'll create or modify and wait for my go-ahead. Obey all rules in `CLAUDE.md` —
> especially: one phase only, data-driven, square-grid + Y-sort (not true iso), cozy/no-combat.

Work through `phase00 → phase10` **in order**. Don't start the next until the current one runs and
you've confirmed it. After Phase 5 you'll have the playable cozy core — stop and actually play it.

## Golden rules (also in CLAUDE.md)
- One phase at a time. Runnable beats feature-complete.
- Square-grid TileMap + Y-sort. **Not** true isometric — the angle is only in the art.
- Data-driven items/resources/recipes (`.tres` or JSON), signals over hard node refs, delta-based.
- Cozy, no player combat. Unarmed sprites. No permadeath — cold is a soft penalty.

## Map of the repo
```
CLAUDE.md              # persistent context Claude Code reads every session — the source of truth
README.md              # this file
CREDITS.md             # asset attribution (required by CraftPix licence) — created in Phase 0
setup_assets.sh        # unzip + place the art
raw_assets/            # put the CraftPix .zip files here
docs/
  ASSETS.md            # exact asset paths, frame sizes, licence
  ROADMAP.md           # the 10 phases at a glance + progress
  phases/phaseNN_*.md  # one detailed, paste-ready spec per phase
assets/ scenes/ scripts/ resources/   # the game itself (filled in as phases progress)
```

## Tips for good Claude Code sessions
- Keep sessions to **one phase**. Start a fresh session per phase so context stays clean.
- If Claude drifts (adds combat, goes isometric, hardcodes items), point it back at `CLAUDE.md`.
- Ask it to update `docs/ROADMAP.md` and the "Current status" in `CLAUDE.md` at the end of a phase.
- Commit to git after each working phase so you can roll back.
- When something feels off, tell it to tune the `@export` values rather than rewrite systems.
