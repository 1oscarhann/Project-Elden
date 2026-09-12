# Phase 1 — Player Movement & Directional Animation

**Goal:** a controllable character that walks around a Y-sorted scene with smooth
acceleration and correct 4-direction animations that blend idle ↔ walk ↔ run. This is the
feel-defining phase — get it smooth.

## Assets (import first)
Copy from the character pack into `res://assets/characters/`:
- `Unarmed_Idle_without_shadow.png` (64×64 frames, 12 cols × 4 rows)
- `Unarmed_Walk_without_shadow.png` (64×64, 6 × 4)
- `Unarmed_Run_without_shadow.png`  (64×64, 8 × 4)

**Row order = direction: 0=down, 1=left, 2=right, 3=up.** Columns = frames.
Set import filter to Nearest.

## Scene: `scenes/player/Player.tscn`
Node tree:
```
Player (CharacterBody2D)          # script: scripts/player/player.gd
├── Sprite (AnimatedSprite2D)     # or Sprite2D + AnimationTree; see below
├── Shadow (Sprite2D)             # soft blob under feet, optional (shadow_single.png)
├── CollisionShape2D              # small capsule/rect around the FEET, not the whole 64px
└── Camera2D                      # current = true, position smoothing on
```
Notes:
- The collision shape must sit at the **feet** and be small (~16×8), so the character
  overlaps scenery naturally in 2.5D. The sprite art is much taller than the collider.
- Enable **Y-sort** on the parent world later; the Player's visual sort point is its origin —
  place the sprite so its origin is at the feet.

## Animation approach
Use an **AnimationTree** driving a **SpriteFrames** (`AnimatedSprite2D`) OR blendspaces.
Simplest robust setup for this pack:

1. Build a `SpriteFrames` resource with animations named per state+direction, e.g.
   `idle_down, idle_left, idle_right, idle_up, walk_down, ... run_up` by slicing each sheet's
   rows/cols (64×64). Set walk ~10 fps, idle ~6 fps, run ~12 fps, all looping.
2. In `player.gd`, keep a `facing` vector and a `state` enum {IDLE, WALK, RUN}. Each frame pick
   the animation string `"%s_%s" % [state_name, dir_name]` and call `play()` only when it changes.
3. `dir_name` from facing: pick the dominant axis (down/up/left/right). For 8-way movement you
   still snap the *animation* to the nearest 4-direction (art only has 4).

(If you prefer a proper `AnimationTree` + `BlendSpace2D` per state with a Transition node between
IDLE/WALK/RUN, that's welcome — but the SpriteFrames+string approach is fine and less fiddly.)

## Movement (`scripts/player/player.gd`)
- `CharacterBody2D`, top-down, no gravity.
- Read input as a normalized vector from actions `move_up/down/left/right` (add these to the
  input map; also bind WASD + arrows).
- **Smooth accel/decel** with `velocity = velocity.move_toward(target, accel * delta)`.
  Exposed `@export` vars: `walk_speed`, `run_speed`, `acceleration`, `friction`.
- Hold **Shift** (`run` action) to run (RUN state + run anim + higher speed).
- Update `facing` only when there's input, so idle keeps the last-faced direction.
- `move_and_slide()`.
- Everything uses `delta`.

## Test scene
Put the Player into `Main.tscn` (or a temporary `scenes/main/World.tscn` with `Node2D` +
`YSort` behaviour enabled) over a plain coloured background and a couple of placeholder
`ColorRect`/`Sprite` blocks so I can see Y-sorting and movement feel.

## Definition of done
- Character accelerates/decelerates smoothly, no snappy stops.
- Correct idle/walk/run animation for all 4 facings; idle holds last direction.
- Shift runs. Movement is diagonal-normalized (no faster diagonals).
- Camera follows smoothly.
- Collider is at the feet and small.

## Do NOT
- Add stats, day/night, harvesting, inventory — later phases.
- Add combat.

When done: update ROADMAP + CLAUDE.md status, and tell me the exact `@export` values you chose
so I can tune the feel.
