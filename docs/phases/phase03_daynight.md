# Phase 3 — Day/Night Cycle & Warmth Stat

**Goal:** time passes, the world visibly shifts from day to dusk to night to dawn, and a
**warmth** stat drops at night — setting up the campfire tension in Phase 4.

## New autoloads
- `DayNight` (`scripts/globals/day_night.gd`):
  - Tracks an in-game clock (e.g. a `float time_of_day` in 0..1, plus `day` counter).
  - `@export` a full-day real duration (e.g. 8–12 min for testing; expose it).
  - Emits signals: `phase_changed(phase)` where phase ∈ {DAWN, DAY, DUSK, NIGHT},
    `day_passed(day_number)`, and a continuous `tick(time_of_day)` if useful.
- `GameState` (`scripts/globals/game_state.gd`):
  - Holds `warmth` (0..100, start 100) and later health/hunger. Signal `warmth_changed(value)`.

## Visuals
- Add a `CanvasModulate` to the world; lerp its colour over `time_of_day`:
  warm daylight → orange dusk → cool dark blue night → soft dawn. Keep night **readable**
  (cozy, not pitch black). Interpolate smoothly, driven by `DayNight`.
- Optional: a subtle vignette or a light around the player at night (a `PointLight2D`) so the
  player is never fumbling in the dark — reinforces cozy.

## Warmth logic
- During NIGHT (and maybe DUSK), `warmth` decreases over time (delta-based) **when the player is
  not near a heat source**. In Phase 3 there's no campfire yet, so just: warmth drains at night,
  regenerates during day. Expose the rates.
- Warmth is a **soft** stat: at low warmth, apply a gentle penalty (e.g. slower movement, a blue
  screen tint, a shiver particle) — **never** death. Wire the penalty hook now even if minimal.

## HUD stub
- A tiny debug HUD (`scenes/ui/HUD.tscn`) showing day number, current phase, and a warmth bar.
  Keep it ugly/functional; real UI polish comes in Phase 10.

## Definition of done
- Time advances; colour transitions day→night→day look smooth and cozy.
- `warmth` drains at night, recovers by day, shown on the HUD, with a visible low-warmth cue.
- Signals fire correctly (log phase changes).

## Do NOT
- Build the campfire yet (Phase 4) — but structure warmth so a heat source can pause/reverse the
  drain by the player simply being within a radius.

Update ROADMAP + CLAUDE.md.
