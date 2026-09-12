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

---

## Iteration 3 — Task 4: code cleanup

**System changed:** code cleanup (naming, docstrings, splitting the one
over-length script). No behaviour changed anywhere in this iteration — every
change is either a pure extraction (same logic, new location) or a comment.

### Naming conventions: audited, already clean

Scanned every non-addon script for camelCase identifiers, PascalCase
vars/funcs, and missing file-level doc comments. **Zero violations found** —
the codebase already follows GDScript's snake_case/PascalCase/SCREAMING_SNAKE
conventions consistently. No changes made.

### Split `battle_manager.gd`: 367 → 301 lines

It was the only script over the ~300 line guideline. Pulled three
single-responsibility, independently-testable pieces out of it — pure
functions with no dependency on BattleManager's instance state:

| New file | Extracted from | What it does |
|---|---|---|
| `scripts/combat/enemy_ai.gd` | `_choose_enemy_action` | Picks an enemy's move: attack vs. best-scoring skill against the target's type, gated by aggression |
| `scripts/combat/battle_log.gd` | `_describe`, the item-effect text in `_resolve_item` | Turns a resolved action into the line of text the player reads |
| `scripts/combat/battler_group.gd` | `_alive`, `_random_living_foe`, `_has_boss` | Pure queries over a side's Battler array |
| `Combat.flee_chance()` (added to existing `combat.gd`) | the inline math in `_try_flee` | The escape-odds formula, now a named, testable function instead of inline arithmetic |

`battle_manager.gd` now only owns the turn state machine and signal wiring;
it calls into these four instead of doing the work inline. Every constant
used in the extracted math (`0.02` speed weight, `0.05`/`0.95` clamp bounds)
kept its exact value — confirmed byte-for-byte via `test_battle_helpers.gd`'s
bound checks and the untouched `test_battle_flow.gd` suite still passing
unchanged.

Added `test/unit/test_battle_helpers.gd` (17 tests) covering the four
extracted pieces directly — the whole point of pulling them out was to make
them testable without spinning up a battle, so this cashes that in rather
than just asserting via existing higher-level battle tests.

### Docstrings: 42 missing, now 0

Scanned every public (non-underscore, non-lifecycle) function across
`scripts/` for a preceding `##` doc comment. Found 42 missing, spread across
`audio_manager.gd`, `battle_manager.gd`, `game_state.gd`, `save_manager.gd`,
`battler.gd`, `encounter_table.gd`, `move_data.gd`, `battle_ui.gd`,
`encounter_zone.gd`. Added one to two lines each, explaining what the
function does and, where it wasn't obvious from the name, why (e.g.
`store_vitals()` now says it's the *only* path that lets a battle's outcome
reach a save). Re-ran the scan after: zero missing.

### Verification

- 121 tests, 835 asserts, all green (104 existing + 17 new for the split).
- Grepped for leftover references to the four removed private helpers
  (`_describe`, `_alive`, `_random_living_foe`, `_has_boss`) — none found
  outside the new modules and their legitimate `Battler.is_alive()` calls.
- Project launches clean, headless.

### Self-check

- [x] Project launches without errors
- [x] All GUT tests green (121/121, 835 asserts)
- [x] No model/texture/shader/animation touched
- [x] No UI touched (`battle_ui.gd` only gained a docstring, no structural
      or visual change)
- [x] Only ONE system changed (code cleanup — naming/docstrings/split, pure
      refactor, zero behaviour change)
- [x] Committed

---

## Iteration 4 — Task 6 (partial: UI structure fix); Tasks 5 & 7 confirmed SKIP

**System changed:** UI structure (`battle_ui.gd`). Nothing else.

### Task 6, part 1 — theme resource: SKIPPED

"Make every UI element use the existing theme resource" assumes one exists.
**None does** — checked for any `.theme` file or `Theme` resource anywhere in
the project; there is none. `BattleUI` sets font sizes directly
(`add_theme_font_size_override`) because there's nothing else to point at.
Creating a Theme resource now would mean choosing colours and fonts, which
is explicitly out of bounds for this pass ("NEVER invent colours, fonts, or
redesign UI"). Logging this rather than guessing — a theme resource is a
design artefact, not a code cleanup.

### Task 6, part 2 — anchor/margin overflow: found a real bug, fixed it

Rather than reasoning about the anchor math by eye, wrote
`test/unit/test_ui_layout.gd`, which actually instantiates `BattleUI`,
drives it through real gameplay (the actual hero content, levelled up
through `GameState.award_xp()` — not fabricated data), and reads back real
`Control` rects from the live scene tree.

**Confirmed a genuine, currently-reachable overflow**: the skill menu's
button list was a plain `VBoxContainer` inside a fixed-height panel
(224px). By level 5, the hero's real learnset (Frost, Radiance, Gale, Mend
on top of the starting Cleave and Ember — SPEC content, reached by normal
levelling, no new content needed to trigger it) grows to 6 moves + "Back" =
7 buttons, and the panel's forced minimum size pushed the last button 25px
past the bottom of the 720px canvas (measured: button bottom edge at
y=745). This is exactly the class of bug Task 6 asks to catch.

**Fix**: wrapped the button list in a `ScrollContainer`. This is a
structural fix, not a styling one — a `ScrollContainer` breaks minimum-size
propagation, so the panel's on-screen footprint stays fixed at its intended
224px regardless of how many buttons a menu holds; anything that doesn't
fit scrolls instead of spilling past the canvas or encroaching on the log
panel to its left. No colour, font, or spacing value was invented or
changed.

Getting the test right took two passes: the first version asserted every
button's raw global position was on-canvas, which is the wrong invariant
for a scrollable list — a scrolled-out button is *supposed* to sit beyond
the visible viewport; that's what scrolling means. Rewrote it to check what
actually matters: the `ScrollContainer`'s own (clipped) viewport stays
on-canvas, `clip_contents` is actually enabled (so overflow content is
truly never drawn outside it), and — to catch the fix trading a visual bug
for a worse one — that scrolling to the bottom actually brings "Back" fully
into view. A clipped-but-unreachable "Back" button would be a softlock,
which is worse than the original overflow.

**On "verify at both 1920x1080 and 1280x720":** the project runs
`canvas_items` stretch mode with a fixed 1280x720 logical canvas
(`project.godot` `[display]`). Both target resolutions are 16:9, so 1080p
is not a second layout — it's the same 1280x720 canvas scaled uniformly by
1.5x. Uniform scaling of a matching aspect ratio cannot introduce an
overflow that isn't already present at the base resolution; what actually
varies is *content* (how many buttons a menu holds), which is what the test
drives instead. Stated explicitly in the test file rather than left as an
unstated assumption.

### Task 5 — model integration: SKIP confirmed again

`/assets/packs/` still does not exist (re-checked; unchanged since
iteration 1). Placeholder capsules remain. Nothing to import.

### Task 7 — animation wiring: SKIP, newly confirmed

Checked for any imported model file (`.glb`/`.gltf`/`.fbx`/`.dae`) and any
`AnimationPlayer`/`AnimationTree` node in any scene: **none exist**. There
is nothing to hook idle/walk/attack state to. This follows directly from
Task 5's precondition also being unmet — no models means no animations
shipped with them.

### Observed but not fixed (outside every task, logged only)

`project.godot`'s `[rendering]` section is missing the explicit
`renderer/rendering_method="forward_plus"` and
`renderer/rendering_method.web="gl_compatibility"` lines the original spec
called for (SPEC §4: "Web renderer | Compatibility / WebGL 2 | The stable
shippable target"). It currently has `.mobile="gl_compatibility"` instead of
`.web`. This predates this hardening loop entirely — it happened inside the
original vertical-slice commit (`e7177a2`), most likely because a
`ProjectSettings.save()` call from `scripts/tools/setup_input.gd` rewrote
the file and dropped the value matching the compiled default (`forward_plus`
needs no override) while also losing the `.web` override along the way.
Not one of the seven listed tasks, and fixing project render settings isn't
"UI structure" — flagging it here rather than touching it, since silently
"fixing" something outside the task list is exactly the kind of invented
work this pass is supposed to avoid.

### Self-check

- [x] Project launches without errors
- [x] All GUT tests green (124/124, 859 asserts)
- [x] No model/texture/shader/animation generated — none exist to touch,
      confirmed by re-checking the gate
- [x] No UI colours/fonts invented — only a `ScrollContainer` (structure)
      was added; the missing theme resource itself was skipped, not
      papered over
- [x] Only ONE system changed (`battle_ui.gd` + its test)
- [x] Committed

---

## Loop complete

All seven tasks in the priority list have been addressed:

| # | Task | Outcome |
|---|------|---------|
| 1 | GUT test suite | Done (iteration 1) |
| 2 | Hardcoded stats → `.tres` | Already done before this loop; verified (iteration 2) |
| 3 | Save/load hardening | Done — two defects fixed, one limitation logged (iteration 2) |
| 4 | Code cleanup | Done — split `battle_manager.gd`, docstring pass (iteration 3) |
| 5 | Model integration | SKIP — `/assets/packs/` doesn't exist |
| 6 | UI structure | Partial — overflow bug fixed; theme-resource part SKIP (no theme exists) |
| 7 | Animation wiring | SKIP — no models/animations exist |

Per the loop's own rule ("If you run out of listed tasks: STOP. Do not
invent work"), this is the end of the pass. Final state: 124 tests, 859
asserts, all green; project launches clean; four commits, each a single
system, each bisectable.
