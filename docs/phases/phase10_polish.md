# Phase 10 — Save/Load & Polish Pass

**Goal:** persistence + the juice/feel pass that makes it feel like a real cozy game.

## Save/Load
- JSON save to `user://save_XX.json`. Serialize: player position, `GameState` (warmth/health/
  hunger/day), `DayNight` time, `Inventory` slots, placed buildings (type + grid pos + state),
  campfire fuel, harvestable states/timers, animal population (optional/simplified).
- `SaveManager` autoload: `save_game(slot)`, `load_game(slot)`, `has_save(slot)`. Version the save
  format (`"version": 1`) so future changes don't break old saves.
- A simple main menu (`scenes/ui/MainMenu.tscn`): New / Continue / Quit. Autosave on sleep/day-end
  is a nice touch.

## Polish checklist
- **Tweens** everywhere UI appears/changes: panels, item pickups (fly-to-hotbar), menu pops.
- **Particles** (`GPUParticles2D`): footstep dust, harvest bursts, campfire embers/smoke, leaves
  in wind, a few fireflies at night for cozy vibes.
- **Screen shake**: subtle on harvest/impact only (already added Phase 5 — tune it down if needed).
- **Audio**: ambient loop (waves/birds by day, crickets by night), footstep sfx, harvest chops,
  fire crackle, craft/pickup blips, gentle music. (Source cozy CC0 audio; add a credits line.)
- **Feedback**: floating "+1 wood" pickup text; low-warmth blue vignette + shiver; day-change
  toast ("Day 3").
- **Transitions**: fade between interior/exterior and on load.
- **Pixel-perfect check**: no jitter when the camera moves; snap camera to pixels.
- **Settings**: volume sliders, fullscreen toggle, maybe a day-length slider.

## Definition of done
- Can save and reload a session faithfully.
- The game *feels* cozy and alive: sound, particles, smooth UI, readable feedback.
- No obvious jank in movement, sorting, or transitions.

## After this
Ship a build (desktop export; test web export). Write a short README + itch.io page. Then it's
content: more recipes, more islands, seasons, whatever you fancy — all data-driven now.

Update ROADMAP + CLAUDE.md (mark project v1 complete).
