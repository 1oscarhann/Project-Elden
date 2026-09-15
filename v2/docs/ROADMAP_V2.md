# ROADMAP_V2.md — Post-v1 Features (do NOT start until Phases 0–10 ship)

These are **v2** ideas, agreed after the core game. **Rule: ship v1 (Phases 0–10) completely
before touching any of this.** A finished small game beats an unfinished big one. This doc just
saves the direction so it's ready when the time comes. Everything here is data-driven-friendly
because v1 was built that way — most of it is new `.tres` files + a system, not a rewrite.

## Confirmed for v2 (in rough build order)

### 0. Hunger & Thirst  ✅ definite — do this FIRST in v2
- Full spec already written: `docs/phases/phase11_hunger_thirst.md`.
- Two new `GameState` stats (hunger, thirst) draining over time, same soft-penalty/no-death
  philosophy as warmth. Eating restores hunger (cooked > raw — rewards Phase 7 cooking). Thirst
  needs a real freshwater source (sea water doesn't count) — start with a pond/spring, add a
  craftable waterskin later if wanted.
- Do this before the other v2 items: weather will want to interact with these stats (e.g. rain

### A. ~~Seasons~~ — CUT
Deliberately cut. No season system. Day/night (Phase 3) stays as the only time-based cycle.

### B. Weather  ✅ (standard game weather, no season dependency)
- Rain, clear, fog, snow. A weather state machine with weighted random chance — NOT tied to
  seasons (since there are none); just picks weather periodically/randomly, maybe biased toward
  clear most of the time for cozy pacing.
- Rain/snow = particle overlay + ambient darkening; **rain makes fires burn down faster / harder
  to light**, snow (if it occurs at all without seasons — consider dropping snow specifically,
  keep rain/clear/fog) accelerates warmth loss. Weather feeds the warmth system via signals.

### C. Cooking  ✅ (at minimum simple; depth optional)
- **Minimum (fold into Phase 7):** raw_meat + campfire → cooked_meat. Cooked food restores more
  warmth/energy than raw. You already have raw + cooked icon sheets.
- **Depth (optional, later):** multi-ingredient recipes → dishes with different restore profiles.
  A "cooking station"/pot as a crafting station. All just more `RecipeData` `.tres` files.

### D. Fishing  ✅ (design updated)
- **Not** available at any water tile — fishing is unlocked via an **abandoned fishing spot**
  found somewhere on the island (a derelict dock/jetty, using the fishing-village pack — net
  rack, drying rack, dock/jetty pieces already collected in `assets/farming/` or wherever that
  pack landed).
- The spot starts broken/derelict (missing planks, rotted, non-functional). Player **repairs it**
  using a SMALL, deliberately short list of gathered materials (e.g. a handful of planks + rope/
  fibre — keep it to 2-3 ingredient types, not a long list) via the existing Crafting system as a
  one-time "repair" action at the location, not a craftable item.
- Once repaired, the dock becomes a **permanent fixed fishing spot** — interact there to fish
  (simple timing minigame, Phase D's original scope). Fishing should NOT work at generic water
  tiles, only at this (and possibly other, later) repaired spot(s).
- Nice narrative tie-in: fits the "abandoned island, remnants of someone who was here before"
  framing from the opening story moment — the dock is evidence you're not the first person
  stranded here.
- Asset: the fishing/storage pack (net rack, hanging-fish drying rack, dock/jetty pieces, fish
  haul crate) — use for the dock scene itself and the "fish caught" display/storage nearby.
- Interact at a water-edge tile → simple timing/minigame → fish item (fish icons already in the
  food sheet). Fish become cookable ingredients. Keep the minigame tiny and cozy.

### E. Farming  ✅
- **Asset ready:** CraftPix "Free Pixel Art Plants for Farm" pack — staked crop plants at
  multiple growth stages (sprout → mature, paired for progression), grapevines, berry bushes,
  fruit trees with growing fruit, palms, sunflowers, seedlings. CraftPix free licence, attribution
  required. Saved in `assets/farming/` for when this item is built — don't wire in before v2.
- **Reuses the Phase 5 growth-stage system** (`_1/_2/_3` sprites) directly as crop stages.
- Till a plot (grid tile) → plant seed → grows over in-game days (advanced by `DayNight`) →
  harvest. No season-gating (seasons cut) — crops are plantable/growable year-round.
- Watering optional. Crop definitions are data (`CropData` resource).

### F. Warmth gear (esp. winter)  ✅
- Reframe the **armour icon sheet** as warm clothing: coat, cloak, hat, gloves, boots.
- Simple equip slots; equipped gear **reduces warmth drain rate** (stacking or per-slot).
- Gives the **ore → smithing → crafting tree an actual payoff**: mine → workbench/forge → gear →
  survive winter. Closes a loop that otherwise dead-ends.
- `EquipmentData` resource + a small equip UI; hook into the warmth calc via a modifier.

## Deliberately OUT
- **NPCs / dialogue / companions** — cut. Keeps the solo-cozy vibe and dodges the biggest
  scope-sink. Don't reopen this without a very good reason.

## Undecided (defer the call to after v1)
- **Multiple islands + sailing (raft).** Biggest scope jump: new world-gen, a sailing mode, and
  much more complex saves. Decide *after* v1 ships, once you know whether you want the game bigger.
  If yes: build a raft (crafting), a simple sail transition, and generate a fresh island scene.

## Sequencing note
Good v2 order: **Hunger/Thirst (0) → Snappy-feel pass (H) → Weather (B) → Farming (E) → Cooking
depth (C) → Fishing (D) → Warmth gear (F) → Shallow wading (G)**. Weather (B) has no season
dependency now (seasons cut) so it can move earlier if wanted. Islands (if ever) last.

### G. Shallow water wading  ✅ definite (simple version)
- Player can wade into **shallow water at the beach edge** (slower movement, splash particle,
  maybe a wet-footstep sound); **deep/open sea stays a hard collision wall** as it is now — this
  is wading, not full swimming.
- Needs: a shallow-water tile/zone distinct from deep water in the terrain (or a radius check
  near shorelines), a movement-speed modifier while in it, and ideally a splash particle on
  entry/steps. Doesn't need a new swim animation — walk anim at reduced speed is fine.
- Nice tie-in: wading in cold weather (once Seasons/Weather land) could tick warmth down slightly
  faster, reinforcing the cozy warmth loop rather than adding an unrelated system.
- Deliberately NOT full open-water swimming — no drowning, no swim animation, no water combat/
  harvesting. If full swimming is ever wanted, treat it as a separate future decision, not part
  of this item.

### H. "Snappy" feel pass — HIGH PRIORITY, not optional polish
This is a CORE REQUIREMENT for the user, not a nice-to-have. Reference: Isocore's responsiveness
and crispness. Every animation and interaction should read as immediate and satisfying — the
opposite of floaty/mushy/delayed. Treat this as a real bar to clear, with concrete, testable
targets below — not a vague "make it feel nice" note.

**What "snappy" means here (be precise, don't approximate):**
- **Input → response is near-instant.** No wind-up frames before an action starts. Pressing a key
  should visibly do something within 1-2 frames, always.
- **Movement acceleration AND deceleration are both fast.** Short `move_toward`/lerp ramps in
  BOTH directions — reaching top speed quickly, and stopping quickly when input releases. No
  skating/drifting after the player lets go of a direction. This is the single most noticeable
  lever for "does this feel good to move."
- **Actions are short and interruptible.** Harvesting/interacting should not lock the player into
  a long uncancelable animation — keep action windows tight, allow movement to resume quickly.
- **Impact feedback is sharp, not gentle.** Hitstop (2-4 frame freeze on impact), fast-decaying
  screen shake (sharp spike then quick fade, never a slow float), squash-stretch tweens with a
  quick snap-back ease, not a slow ease-out. The IMPACT reads instantly even if the animation
  around it is soft.
- **Animations are crisp, not smeared.** Prefer a few well-timed, clearly-posed frames over many
  smooth in-between frames — snappy games often read faster with FEWER frames held with intent,
  not more frames blurred together.
- **Audio hits immediately**, no fade-in on interact/impact/pickup sounds.
- **UI responds instantly** — menu opens/closes, button presses, inventory updates should feel
  as crisp as the gameplay, not sluggish tweens.

**What it does NOT mean (stay cozy in tone):**
- Not violent, not aggressive, not combat-coded. The SNAP is in timing and responsiveness, not
  in intensity or harshness. Soft colour palette, gentle (but SHARP-timed) particles, no gore.
  Think "a well-made cozy game that feels great to control," not "an action game."

**How to verify this actually landed (don't just take Claude Code's word for it):**
- Movement: does the character stop within a couple of frames of releasing input, with zero
  drift/slide? If there's any noticeable "skating," it's not fixed yet.
- Harvesting: does the hit register immediately on the swing, with a visible sharp reaction
  (shake/flash/particle) at the exact frame of impact, not slightly after?
- Compare side-by-side against a game known for this feel (Isocore, or similar tight action-
  cozy hybrids) if unsure — the difference between "snappy" and "just okay" is usually obvious
  once you're looking for drift/delay specifically.

Apply as a dedicated review-and-tune pass across Phase 1 (movement), Phase 5 (harvest), Phase 9
(hunting), and Phase 6/7 (UI) once v1 ships. Given how important this is, consider doing this
pass EARLY in v2, right after Hunger/Thirst, rather than saving it for last.
