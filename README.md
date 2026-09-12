# Project Elden

A 3rd-person, turn-based single-player RPG in the Pokémon/Persona lineage.
Built in Godot on desktop, shipped to the web.

**Status:** vertical slice implemented — overworld, encounters, full combat
loop with One More, data-driven content, save/load, and a boss. Placeholder
art throughout, by design.

## Run it

Open the project in **Godot 4.7 stable** and press play. `World.tscn` is the
main scene.

| Input | Action |
|-------|--------|
| `WASD` / arrows | Move (camera-relative) |
| Mouse / `IJKL` | Camera |
| `Space` | Jump |
| `F5` | Quick save to slot 0 |
| `Esc` | Release the mouse |

Walk around to trigger encounters. The purple arch to the north is the boss —
the Warden is only weak to **light**, and the hero learns Radiance at level 3,
so go and level up first.

## Tests

```bash
GODOT=/path/to/godot ./run_tests.sh
```

**121 tests / 835 assertions**, headless, exits non-zero on failure. Run with
[GUT 9.7.1](addons/gut) (vendored in `addons/gut/`, suite in `test/unit/`).
Covers the type chart, the damage formula (multipliers, variance bounds, the
minimum-1 floor), One More, progression and stat growth, save round-trips
field-by-field including through disk, content loading, the turn machine, and
both scenes actually booting. CI runs the same thing plus a backend import
check.

Progress on the hardening pass is logged in [`PROGRESS.md`](PROGRESS.md).

## Docs

- [`docs/SPEC.md`](docs/SPEC.md) — the spec. Scope, stack, combat design, save
  schema, build order, and the decisions taken during review.
- [`docs/REVIEW.md`](docs/REVIEW.md) — technical pushback on the spec, plus an
  appendix of the silent failure modes hit while building the slice.
- [`backend/README.md`](backend/README.md) — the save API.

## Layout

```
scenes/                 World.tscn (overworld), Battle.tscn (combat)
scripts/autoload/       GameState, BattleManager, SaveManager, AudioManager
scripts/combat/         type_chart.gd + damage.gd (combat identity), plus
                        enemy_ai.gd / battle_log.gd / battler_group.gd —
                        pulled out of battle_manager.gd to keep it under
                        ~300 lines and independently testable
scripts/data/           Resource definitions + ContentDB loader
scripts/world/          player controller, encounter zone, boss gate
scripts/ui/             combat UI
scripts/tools/          content and scene generators (run as scenes, not --script)
data/                   enemies, moves, items, party, encounters — all .tres
test/unit/              GUT suite
addons/gut/             GUT 9.7.1 (vendored; exclude from the web export)
backend/                FastAPI + Neon save API
```

## Adding content

Pillar 2 of the spec: new content is a new file, never new code.

Drop a `.tres` into `data/enemies/`, `data/moves/` or `data/items/` and
`ContentDB` picks it up by its `id` on next load. No registration step. To
retune the whole starting set at once, edit
`scripts/tools/generate_content.gd` and run:

```bash
godot --headless --path . res://scripts/tools/generate_content.tscn
```

## Where this is in the build order

Steps 1–7 are done (step 7's backend is written and compiling but **not
deployed**). Next up is step 8: the combat UI polish pass and audio, then the
web export. See `docs/SPEC.md` §9.

## Known gaps

- Combat UI is functional, not designed — built in code, no theme.
- No audio assets yet; `AudioManager` is wired but has nothing to play.
- No dialogue system yet (`data/dialogue/` is empty).
- Web export has not been run — needs export templates and a real device test.
- Desktop input only. A browser link will get opened on a phone eventually.
