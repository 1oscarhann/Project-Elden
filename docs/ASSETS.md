# Asset requirements

What the code is currently wired for. Everything here is derived from the
actual scenes and `data/**/*.tres`, not from a wishlist — the scale numbers
are the placeholder primitives' real dimensions, so a model built to them
drops in without re-tuning the camera or the battle stage.

**Status:** nothing has been sourced yet. `assets/packs/` is empty, which is
why build-order steps for model integration and animation wiring are logged
as SKIPPED in [`PROGRESS.md`](../PROGRESS.md).

---

## 1. The five models

Five characters. Everything else — ground, blockers, the boss gate — can stay
greybox for now (see §5).

| Asset | Content id | Size (H × R, metres) | Reads as | Placeholder colour |
|-------|-----------|------|----------|--------------------|
| Wanderer (player) | `hero` | 1.8 × 0.4 | neutral / physical | off-white `#D9D1B3` |
| Frostbit | `frostbit` | 1.8 × 0.4 | ice — cold, brittle, pale | `#73BFF2` |
| Emberling | `emberling` | 1.8 × 0.4 | fire — hot, aggressive | `#F27340` |
| Gustling | `gustling` | 1.8 × 0.4 | wind — fast, light | `#99E699` |
| **Warden of the First Gate** | `warden` | **2.4 × 0.6** | dark, boss — should read as a wall | `#593380` |

Colours are `EnemyData.placeholder_color` (`data/enemies/*.tres`), used for the
capsule tint until real materials land. They're a guide to the intended read,
not a palette to match.

### Budget note worth taking

Frostbit, Emberling and Gustling are mechanically identical — same size, same
role, same single-move AI. **One creature mesh with three material variants
covers all three**, at roughly the cost of one. That matters against the 30 MB
web budget (SPEC §8) more than any other single decision on this list.

---

## 2. Hard technical requirements

- **Format: `.glb`** (binary glTF). Godot 4.7 imports it cleanly with textures
  embedded. `.fbx` works but adds a conversion step and more ways to go wrong.
- **1 unit = 1 metre.** Packs that ship centimetre-scale (common with FBX) need
  a 0.01 import scale.
- **Origin at the feet**, centred on X/Z. The current placeholders are
  centre-origin capsules, so `battle_scene.gd` positions them at
  `capsule.height * 0.5`; that offset goes away when real models land (§4).
- **Forward is `-Z`.** Godot convention. A model facing `+Z` will moonwalk and
  needs a 180° correction node.
- **Poly budget: low.** ~1–5k tris each is plenty.
- **Textures 512² or 1024², ideally one shared atlas across the pack.** This is
  the single biggest lever on download size.

---

## 3. Animations

This is what unlocks animation wiring, currently skipped for lack of anything
to hook. Animations must be **baked into the `.glb` as named tracks** — if the
pack ships an unrigged mesh, or animations as separate files, you get static
models and the wiring stays skipped.

**Player** — only what `player_controller.gd` can currently drive:

| Clip | Driven by |
|------|-----------|
| `idle` | horizontal velocity ≈ 0 |
| `walk` | horizontal velocity > 0 |
| `jump` *(optional)* | `is_on_floor()` false; the input action already exists |

**Enemies:**

| Clip | Driven by | Priority |
|------|-----------|----------|
| `idle` | default state | required |
| `attack` | `BattleManager.action_resolved` | required |
| `death` | `Battler.died` | required — currently a crude scale-to-zero tween, so a real clip is a visible upgrade |
| `hit` / `flinch` | `Battler.take_damage()` | nice to have |

---

## 4. What changes in code when assets land

So the wiring work is understood up front rather than discovered:

- `scripts/battle/battle_scene.gd::_spawn_enemies()` — swap `CapsuleMesh` +
  `placeholder_color` material for the model scene; drop the
  `capsule.height * 0.5` Y offset once models are feet-origin.
- `scripts/tools/generate_scenes.gd::_player()` — replace the `Body` capsule
  and the red `Facing` nub under `Player/Model` with the player model.
- `EnemyData` — gains a model path/`PackedScene` field so the mapping stays
  data-driven (pillar 2: new content is a new file, not new code).
- `AnimationTree` per character, driven by the signals in §3.

Filename → id mapping is on me; any folder structure inside `assets/packs/` is
fine as long as it's clear which file is which of the five.

---

## 5. Environment: deliberately not on this list

**The 30 MB budget dies in the environment, not the characters.** Five
low-poly rigged characters is a couple of MB. A detailed zone with baked
lightmaps is tens — and baking is a download *cost*, not a saving
(`docs/REVIEW.md`).

Recommendation: keep the ground, blockers and boss gate greybox until the
characters are in **and a real web export has been measured**. That measurement
is build-order step 9 and hasn't happened yet, so any environment art bought
now is bought blind.

---

## 6. Where to look

Verify licences yourself before shipping — this is general knowledge, not a
live check, and terms change.

| Source | Licence | Fit |
|--------|---------|-----|
| **Quaternius** | CC0 | Best fit for all five — low-poly, rigged *and* animated, ships glTF |
| **Mixamo** | Free (Adobe account) | Strongest option specifically for the Wanderer; huge animation library |
| **Kenney** | CC0 | Reliable, but many character packs aren't rigged with what §3 needs |
| **Synty POLYGON** | Paid | Much better looking; usually FBX, animations often a separate purchase |

---

## 7. Handover

Drop files in **`assets/packs/`**. That exact path is what model integration is
gated on. Once anything is in there, the wiring in §4 becomes actionable.
