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
