# Project Elden — working notes

A 3rd-person, turn-based single-player RPG in the Pokémon/Persona lineage.
Godot 4.7, GDScript, desktop-first, intended to ship to the web.

**Read [`docs/SPEC.md`](docs/SPEC.md) first** — it's the source of truth for
scope, stack and build order. [`docs/REVIEW.md`](docs/REVIEW.md) is technical
pushback on that spec plus an appendix of silent failure modes.
[`PROGRESS.md`](PROGRESS.md) logs the hardening pass iteration by iteration.

---

## Current state

The vertical slice is playable. Build-order steps 1–7 are done.

| Area | State |
|------|-------|
| Overworld | `CharacterBody3D` + `SpringArm3D` chase camera, greybox zone, distance-based random encounters, one-shot boss gate |
| Combat | Full signal-driven turn state machine with **One More**, type chart, single damage function, 5 actions |
| Content | 12 moves, 4 enemies (3 trash + 1 boss), 2 items, 1 party member — all `.tres`, loaded by id |
| Progression | XP curve, per-level stat growth, learnset |
| Save | Local JSON to disk, version-checked, 256 KB cap; cloud sync written but never on the boot path |
| Backend | FastAPI + Neon schema — **written and compiling, NOT deployed** |
| Art | Placeholder capsules. Deliberate — see below |
| Web export | **Never run.** The 30 MB budget is untested |

**Tests: 124, 859 asserts, all green.** Run them before and after any change:

```bash
GODOT=/path/to/godot ./run_tests.sh
```

Or directly:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

Pinned to **Godot 4.7 stable**. Older 4.x will complain on open.

---

## Traps that have already cost time

Read this section before writing tooling or tests. Every one of these fails
*silently*.

### `--script` MainLoops don't have autoloads

`godot --headless --script foo.gd` does **not** register autoload singletons as
GDScript globals. Any script referencing `GameState` or `BattleManager` fails
to compile, and `load()` returns `null` **without raising**.

This bit twice: the scene generator wrote `World.tscn` and `Battle.tscn` with
the root script and boss-gate script silently *missing* (scenes packed fine,
just hollow), and the test suite reported **48 passed, 0 failed** while every
autoload had degraded to a bare `Node`.

**Therefore: tools and tests run as SCENES, never `--script`.** See
`scripts/tools/*.tscn` and `test/unit/`. `scripts/tools/generate_scenes.gd`
has a `_require_script()` guard that aborts rather than writing a scene with a
hole in it. The suite's first test asserts all four autoloads kept their
scripts.

> A green suite that tests nothing is worse than a red one. If a test run gets
> faster or quieter after a refactor, check it still fails when you break
> something on purpose.

### Shared enums must not live on autoloads

Anything that `preload()`s an autoload's script to read an enum compiles that
script too early and triggers the above. Shared constants live in plain
`class_name` scripts: `Combat` (`scripts/combat/combat.gd`) and `SaveFormat`
(`scripts/data/save_format.gd`).

### GDScript lambdas capture by value

```gdscript
var out := []
sig.connect(func(x): out = [x])      # never escapes the closure
sig.connect(func(x): out.append(x))  # works — arrays are references
```

The first form made a battle test hang forever waiting on an end state that had
already been reached.

### `_get` / `_set` are taken

A private helper named `_get(path)` collides with `Object._get(StringName)` and
fails the whole script with "the function signature doesn't match the parent".
`SaveManager._get` is now `_http_get`. Same trap waits on `_set`, `_init`,
`_notification`.

### `add_child()` on the tree root during `_ready()` fails

"Parent node is busy setting up children" — the call is refused and returns
without raising. Use `get_tree().root.add_child.call_deferred(node)`.

### GUT version

GUT **9.3.0 hangs forever** under Godot 4.7 headless with no output. **9.7.1**
works and is 3.2 MB instead of 12 MB. It's vendored in `addons/gut/`.

### `ProjectSettings.save()` rewrites `project.godot`

`scripts/tools/setup_input.gd` calls it, and in doing so it dropped the
explicit `renderer/rendering_method="forward_plus"` and
`renderer/rendering_method.web="gl_compatibility"` lines the spec calls for,
leaving a `.mobile` override instead. **This is currently broken in the repo**
and logged in `PROGRESS.md` — it was out of scope for the hardening pass. Worth
fixing before the web export.

### `ScrollContainer` has an internal `_focus` child

It matches a `find_children("*", "PanelContainer", ...)` type query, so a
"there should be exactly one PanelContainer" assertion will fail. Look nodes up
by name instead.

---

## Design invariants — don't break these

These are load-bearing. Changing one is a deliberate decision, not a refactor.

1. **The damage formula lives in ONE function** — `Damage.calculate()`
   (`scripts/combat/damage.gd`). Never scatter it. Mechanics change its
   *inputs* or get a named modifier inside it.

2. **Content is data, never code.** Enemies, moves, items and party members are
   `.tres` in `data/`, loaded by id through `ContentDB`. Adding content =
   adding a file, no registration step. Ids in code (`&"hero"`, `&"potion"`)
   are *lookups*, not values.

3. **One More is the combat's identity.** A weakness hit or a crit grants the
   attacker one extra action, capped once per actor per round
   (`Combat.ONE_MORE_ENABLED`). Without it this design is Pokémon with a
   Persona coat of paint — weakness becomes just a damage multiplier instead of
   changing the turn economy. It's why the type chart is worth *learning*.

4. **Battle never runs inside the overworld.** `World.tscn` is unloaded during
   combat. Player position and zone round-trip through `GameState`, which is
   the only seam.

5. **`store_vitals()` is the only path from combat into a save.** A mid-fight
   `Battler` HP change is uncommitted until then. `to_dict()` deliberately
   reflects the last *committed* state.

6. **`from_dict()` replays the growth curve rather than trusting stats from the
   blob.** Only the level number is trusted — the client isn't authoritative
   and the curve may have been retuned. Its replay passes `announce = false` so
   loading doesn't fire a level-up signal per level.

---

## Layout

```
scenes/            World.tscn (overworld), Battle.tscn (combat)
scripts/autoload/  GameState, BattleManager, SaveManager, AudioManager
scripts/combat/    type_chart.gd + damage.gd (the identity), plus
                   enemy_ai.gd / battle_log.gd / battler_group.gd / combat.gd
scripts/data/      Resource definitions + ContentDB loader + save_format.gd
scripts/world/     player controller, encounter zone, boss gate
scripts/battle/    battle_scene.gd — builds the stage and UI at runtime
scripts/ui/        battle_ui.gd — combat UI, built in code not as a .tscn
scripts/tools/     content + scene generators (RUN AS SCENES, see traps)
data/              enemies, moves, items, party, encounters — all .tres
test/unit/         GUT suite (11 files)
addons/gut/        GUT 9.7.1, vendored — exclude from the web export (3.2 MB)
backend/           FastAPI + Neon save API
```

`World.tscn` and `Battle.tscn` are **generated**, not hand-authored:

```bash
godot --headless --path . res://scripts/tools/generate_scenes.tscn
godot --headless --path . res://scripts/tools/generate_content.tscn
```

---

## Known limitations — logged, deliberate, not bugs to "fix" casually

- **Two party members from the same content template collide.**
  `vitals`/`experience` are keyed by `BattlerData.id`, which is the *template's*
  id, not a per-slot instance id. A second recruit of the same class silently
  overwrites the first's HP/SP. Fixing it is a **save-schema change** (per-slot
  keys), not a bug fix. Can't occur today — one party template exists. Pinned
  by a test in `test/unit/test_save_hardening.gd` so a future change is
  deliberate.

- **Placeholder capsules are intentional.** SPEC §10: "Park graphical flexes
  until the game is proven fun." See [`docs/ASSETS.md`](docs/ASSETS.md) for
  exactly what models the code is wired for — scale, format, animation clips.
  Blocked on `assets/packs/` being empty.

- **No theme resource exists.** `battle_ui.gd` sets font sizes inline because
  there's nothing to point at. Creating one means choosing colours and fonts —
  a design decision, not cleanup.

- **Combat UI is functional, not designed.** Built procedurally in code.

---

## What's blocked on what

| Want to do | Blocked on |
|---|---|
| Swap capsules for real models | Assets in `assets/packs/` (see `docs/ASSETS.md`) |
| Wire idle/walk/attack animations | Same — and the models must ship *rigged with named clips baked into the `.glb`* |
| Deploy the save API | A Neon database + Render service; code is ready in `backend/` |
| Web export | Fix the `project.godot` renderer drift first; exclude `addons/gut/`; then **measure** against the 30 MB budget |
| Build zones 2–5 | Nothing technical — this is content work, and it's the part that actually takes months |

---

## Conventions

- GDScript style: `snake_case` functions/vars, `_leading_underscore` for
  private, `SCREAMING_SNAKE` constants, `PascalCase` class names. Audited
  clean — keep it that way.
- Every public function has a `##` docstring. Audited to zero missing; don't
  regress it.
- Keep scripts under ~300 lines. `battle_manager.gd` sits at 301 and was split
  once already to get there.
- Commit per logical change with a message explaining *why*, not just what.
