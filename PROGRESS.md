# Hardening loop — progress log

One system per iteration. Every iteration ends with the project launching and
the full suite green, or it reverts.

Environment: Godot **4.7 stable**, run headless. `./run_tests.sh` (set `GODOT`).

---

## Iteration 1 — Task 1: GUT test suite

**System changed:** the test suite. Nothing else was touched.

### What changed

- Installed **GUT 9.7.1** into `addons/gut/` (imported, not written).
- Replaced the bespoke `tests/TestRunner.tscn` harness with GUT test scripts
  under `test/unit/`. Pointed `run_tests.sh`, CI and `.gutconfig.json` at it.
- Ported every existing assertion and expanded to cover Task 1's list:

| File | Covers |
|------|--------|
| `test_autoloads.gd` | all four singletons exist and kept their scripts |
| `test_type_chart.gd` | every weak / neutral / resist / immune pair, unknown types, full N×N sweep |
| `test_damage.gd` | type multipliers (exact 2x / 0.5x ratios), **variance bounds**, **min 1 damage**, crit, defend, zero-defence guard |
| `test_progression.gd` | XP curve monotonicity, threshold behaviour, **stat growth per level**, learnset, boss-key move |
| `test_save_round_trip.gd` | **every GameState field** snapshotted, round-tripped through JSON, deep-compared; plus the disk path |
| `test_content_db.gd` | loader, id lookups, per-enemy/per-move validity, encounter weighting |
| `test_battle_flow.gd` | turn machine, outcomes, One More cap, actions, encounter hand-off |
| `test_scenes.gd` | both scenes instantiate, keep scripts, and stay 3D |

**Result: 93 tests, 751 asserts, all green.** Project launches clean.

### Why GUT 9.7.1 and not 9.3.0

9.3.0 was installed first and **hung forever** under Godot 4.7 headless with no
output. Swapped to 9.7.1, which runs clean — and is 3.2 MB instead of 12 MB.

### Notes for later iterations

- **`SaveManager.slot_summary()` returns `gold` and `level` as floats.**
  They come straight out of `JSON.parse_string`, which yields floats for all
  numbers, so a save-select screen would render `Gold: 931.0` / `Lv 5.0`.
  This is a production defect, not a test artifact. **Not fixed here** — it is
  a change to SaveManager, and this iteration owns only the test suite. The
  test compares numerically and carries a `KNOWN DEFECT` comment.
  → Fix in the Task 3 save-hardening iteration.
- **`battle_manager.gd` is 367 lines**, over the ~300 line guidance.
  → Task 4 (code cleanup) iteration.
- **`addons/gut/` will be included in a web export by default** (3.2 MB against
  a 30 MB budget). Needs an export-preset exclusion when the web export is set
  up. No export preset exists yet, so there is nothing to configure.

### SKIPPED

- **Task 5 (model integration): SKIPPED — `/assets/packs/` does not exist.**
  The repo has no `assets/` directory at all. The constraint is explicit that
  models may only be imported from that folder and never generated, so there is
  nothing to wire. Placeholder capsules remain. Drop model files into
  `assets/packs/` and this becomes actionable.

### One test was wrong, not the code

`test_a_battle_starts_in_the_player_phase` asserted the phase *after*
`start_battle()` returned. With `turn_delay = 0` the entire fight resolves
synchronously inside that call, so the phase is already `FINISHED`. The test
now samples the phase at the first `awaiting_action` prompt. No production code
changed.

### Self-check

- [x] Project launches without errors
- [x] All GUT tests green (93/93)
- [x] No model/texture/shader/animation generated from scratch — none touched
- [x] No UI colours/fonts invented — no UI touched
- [x] Only ONE system changed (the test suite)
- [x] Committed

---

## Iteration 2 — Task 2 verified done, Task 3: save/load hardening

**System changed:** save/load (`GameState.gd` + `SaveManager.gd`). Nothing else.

### Task 2 status: already complete, verified not re-done

Checked for any hardcoded enemy/move/item **stat** in `scripts/`: none exist.
`&"hero"`, `&"potion"`, `&"ember"` etc. appearing in code are `StringName` ids
looked up through `ContentDB` — references, not values. All actual stats
(hp, attack, power, price, growth curves) live in `data/**/*.tres`, loaded by
`ContentDB._load_dir()`. This was done in the original vertical slice
(`e7177a2`), before this hardening loop began. No code changed for Task 2 this
iteration; moving straight to Task 3 rather than inventing filler work.

The engine-level tuning constants that remain in code (`Damage.VARIANCE_MIN`,
`Combat.BASE_FLEE_CHANCE`, `GameState.XP_CURVE_BASE`, etc.) are formula shape,
not enemy/move/item stats — Task 2 doesn't ask for those to move to data, and
moving them would blur "formula" and "content" in a way the spec doesn't.
Left alone.

### Task 3: two real defects fixed, one edge case documented as a limitation

**Fix 1 — `SaveManager.slot_summary()` returned floats.** Flagged as a known
defect in iteration 1 (GUT's own Float/Int comparison warning caught it).
`_read_slot()` goes through `JSON.parse_string()`, which returns every number
as a float — so a save-select screen would have rendered `Gold: 931.0` /
`Lv 5.0`. Now explicitly `int()`-cast. Regression test:
`test_slot_summary_returns_ints_not_floats`.

**Fix 2 — loading a save re-fired every level-up signal.** `from_dict()`
restores a saved level by replaying `_level_up()` from 1 up to the saved
level (deliberately — stats are never trusted from the blob, only the level
number is, and growth is replayed from the current curve). But `_level_up()`
unconditionally emitted `party_member_leveled`, so loading a level-12 save
fired 11 level-up signals back to back — any UI listening for a "LEVEL UP!"
toast or jingle would fire it 11 times the instant a save finished loading.
Added an `announce: bool = true` parameter; `from_dict()`'s replay passes
`false`, `award_xp()`'s real level-ups keep the default. Regression tests:
`test_loading_a_save_does_not_fire_level_up_signals`,
`test_real_level_ups_still_announce` (guards against over-silencing).

### Edge cases added (`test/unit/test_save_hardening.gd`, 12 tests)

- Empty inventory round-trips and doesn't break `slot_summary()`.
- `slot_summary()` on a missing slot, and on a save with a hand-corrupted
  empty `party` array — both return cleanly instead of crashing.
- A party entry naming content that no longer exists (a renamed/deleted
  `.tres`) is dropped with a warning, not fatal to the rest of the load.
- **Mid-battle state is not touched by save/load**, checked from both
  directions: `to_dict()` reflects the last *committed* vitals, not whatever
  a live `Battler` currently holds mid-fight (only `store_vitals()` commits
  it — SPEC's "never run battle inside the overworld" boundary); and
  `from_dict()` never reaches into `BattleManager`, so loading mid-fight
  can't corrupt an active battle.

### KNOWN LIMITATION — logged, not fixed

**Two party members duplicated from the same content template collide in
`vitals`/`experience`.** Both dictionaries are keyed by `BattlerData.id`,
which is the *content template's* id (e.g. `&"hero"`), not a per-party-slot
instance id. Add two members built from the same `.tres` — including the
starting hero plus any duplicate — and they share one vitals entry; whichever
is added last silently overwrites the earlier ones' HP/SP. Confirmed by
`test_known_limitation_duplicate_content_ids_collide_in_vitals`.

Not fixed this iteration: a real fix means keying saves by party-slot index
(or a generated per-instance id) instead of content id, which is a
**save-schema change** — a different, larger decision than a hardening pass,
and the game currently has exactly one party-member template so it never
manifests in play. Flagging for whoever adds a second recruitable character.

### Self-check

- [x] Project launches without errors
- [x] All GUT tests green (104/104, 774 asserts)
- [x] No model/texture/shader/animation touched
- [x] No UI touched
- [x] Only ONE system changed (save/load: `game_state.gd` + `save_manager.gd`
      + their tests)
- [x] Committed
