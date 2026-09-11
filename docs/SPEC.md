# RPG Project — Spec Sheet

**Working title:** TBD
**Author:** Oscar (3terrabytes)
**Date:** 11 Sept 2026
**Status:** Pre-production

---

## 1. Elevator pitch

A 3rd-person, turn-based single-player RPG in the Pokémon/Persona lineage: explore an overworld, trigger battles, exploit enemy weaknesses in a type-based combat system, level up, and progress through a handful of hand-built zones. Built on desktop in Godot, shipped to the web.

---

## 2. Core pillars (don't betray these)

1. **The battle loop is the game.** If a single fight isn't fun, nothing else matters. Build it first.
2. **Data-driven content.** Enemies, moves, items, dialogue live in data files, not code. New content = new file, no new code.
3. **Web-shippable.** Every asset and system choice is judged against "does this survive a browser build?"
4. **Finish the slice.** One zone, fully polished, beats five zones half-built.

---

## 3. Scope

**Target: Medium.** A vertical slice first, then scale by copy-pasting the proven pattern.

| Tier | Content | Purpose |
|------|---------|---------|
| **Vertical slice** | 1 zone, 3 enemy types, 1 boss, working save | Prove the loop is fun |
| **Full medium build** | 4–5 zones, ~15 enemy types, 3–4 bosses, main quest + a few side quests, progression curve | The shippable game |

Single-player only. No multiplayer (keeps backend and netcode trivial).

---

## 4. Engine & tech stack

| Layer | Choice | Notes |
|-------|--------|-------|
| **Engine** | Godot 4.7 (mainline) | Already known (built Rift). Native HTML5 export. |
| **Language** | GDScript | Cleaner WASM output than C# for web. |
| **Dev renderer** | Forward+ (desktop) | Full-fat while developing. |
| **Web renderer** | Compatibility / WebGL 2 | The stable shippable target. |
| **Web renderer (experimental)** | Godot WebGPU fork | Try at *export time only* as a bonus. Do not build on it. Falls back to WebGL 2 if janky. |
| **Backend API** | FastAPI (Python) on Render | 4 endpoints. Save-file duty only. |
| **Database** | Neon Postgres | Stores accounts + save blobs. Nothing real-time. |

### Architecture

```
Godot 4 web build (browser)
        │  HTTPRequest (REST)
        ▼
FastAPI on Render
        │
        ▼
Neon Postgres  (accounts, save slots)
```

All game logic runs client-side. Neon is a glorified save file.

---

## 5. Godot project structure

**Autoload singletons:**
- `GameState` — party, inventory, gold, story flags, current zone
- `BattleManager` — runs the combat state machine
- `SaveManager` — serialise/deserialise, talks to backend
- `AudioManager` — music + SFX

**Scene split:**
- `World.tscn` — overworld exploration (3rd-person `CharacterBody3D` + `SpringArm3D` camera)
- `Battle.tscn` — separate scene, loaded on encounter, unloaded after. **Never run battle inside the overworld.**

**Data files (the important bit):**
- `enemies/*.tres` (or `.json`) — stats, moves, weaknesses, sprite/model ref
- `moves/*.tres` — damage, type, cost, effect
- `items/*.tres`
- `dialogue/*.json`

---

## 6. Combat system (Persona-style)

- **Turn structure:** state machine — `PlayerTurn → EnemyTurn → CheckWin/Loss → loop`. Signal-driven, not `_process` polling.
- **Type chart:** the core hook. A 2D dict of attack-type vs defend-type multipliers (weak / neutral / resist / immune). Build this early — it's the whole identity of the combat.
- **Damage formula:** lives in **one** function. Never scatter it. Roughly `base × typeMultiplier × (atk/def) × variance`.
- **Actions:** Attack / Skill / Item / Defend / Flee (minimum viable set).
- **Progression:** XP → level → stat growth + new moves at thresholds.

---

## 7. Save data (Neon schema — keep it dumb)

```
accounts
  id            uuid  pk
  username      text  unique
  password_hash text
  created_at    timestamptz

save_slots
  id         uuid  pk
  account_id uuid  fk -> accounts.id
  slot_index int
  data       jsonb   -- entire GameState serialised
  updated_at timestamptz
```

Don't over-normalise. One JSON blob per save is fine and fast.

### API endpoints (that's all you need)
- `POST /register`
- `POST /login`
- `POST /save`   (write blob to slot)
- `GET  /load`   (read blob from slot)

---

## 8. Web performance rules (non-negotiable)

- **Download budget: aim < 30 MB.** Nobody waits for a browser game to load.
- Textures modest resolution + compressed.
- Audio as `.ogg`.
- Bake lighting (no real-time GI on web).
- Test the actual web build on Render **early**, not just desktop. Web threading behaves differently and will surprise you.
- Free wins from 4.7: wasm64 + WASM SIMD (on by default) give headroom for zero effort.

---

## 9. Build order (DO NOT reorder)

1. Overworld movement + 3rd-person camera
2. Encounter trigger → swap to battle scene
3. Combat loop with **one hardcoded enemy**
4. Convert combat to data-driven (json/tres enemies + moves)
5. Local save/load (JSON to disk)
6. Type chart + 3 enemies + 1 boss → **vertical slice done**
7. Wire up Neon backend (accounts + cloud saves)
8. Web export (WebGL 2; try WebGPU fork as bonus)
9. Build out zones 2–5 + quests + progression

> Backend and web export are steps 7–8, not step 1. Nail the fun loop on desktop first.

---

## 10. Risks & honest warnings

- **Content is the killer, not code.** Combat = ~2 weeks. Five zones of content = months. Front-load the slice.
- **The WebGPU fork is beta, pinned to Godot 4.6.2, and maintained by one person for a different product.** Don't build on it — only export through it if it happens to work.
- **Scope creep (e.g. realistic interactive grass) will drown you.** Park graphical flexes until the game is proven fun.
- **"Medium" quietly becomes "full open world" if you let it.** Guard the scope.

---

## 11. Stretch / later

- Cheap wind-shader grass (MultiMesh + scrolling noise) — polish pass only
- Side quests + optional bosses
- New Game+ / harder difficulty
- WebGPU export path once the fork stabilises or Godot ships it natively

---

## 12. Open questions

Raised during review; not yet decided by the author. See `docs/REVIEW.md` for the reasoning.

1. Engine version — pin to the latest **stable** Godot, or accept mainline churn?
2. `.tres` or `.json` for content data? The spec currently says "either" in two places. Pick one.
3. Does the combat get a **One More / press-turn** mechanic, or is weakness-exploitation purely a damage multiplier?
4. `wasm64` — verify it's actually a win before claiming it as one.
5. Is the web build desktop-only, or does it need touch input?
