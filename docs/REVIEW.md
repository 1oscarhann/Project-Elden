# Spec review — technical pushback

Notes on `SPEC.md`. Everything here is either a correctness problem, a
hidden cost, or a design gap. The pillars and the build order are sound
and are not challenged.

---

## Blocking-ish: things that are probably wrong

### 1. `wasm64` is not a free win

The spec lists "wasm64 + WASM SIMD" under *free wins ... for zero effort*.
These two are not comparable:

- **SIMD** — genuinely free. On by default, broad browser support, real gains.
- **wasm64** (Memory64) — not free. It buys a >4 GB address space, which a
  <30 MB game will never need. The costs are real: 64-bit pointers inflate
  the heap and the binary, engine support for it on web has historically
  been experimental, and browser coverage is narrower than baseline wasm32.

For a game whose headline constraint is a 30 MB download budget, wasm64 is
pointed the wrong way. **Recommendation:** ship wasm32 + SIMD. Only touch
wasm64 if profiling shows an address-space wall, which it won't.

### 2. `save_slots` is missing a uniqueness constraint

As written, nothing stops one account from having five rows with
`slot_index = 0`. A `GET /load` then returns whichever row Postgres feels
like. Add:

```sql
UNIQUE (account_id, slot_index)
```

and make `/save` an upsert (`ON CONFLICT (account_id, slot_index) DO UPDATE`)
rather than an insert. Also add an index on `account_id` — you will query by
it on every load.

### 3. Baked lighting is a download-budget *cost*, not a saving

Section 8 puts "bake lighting" in the same list as "compress textures", as
if both shrink the build. Baking trades GPU time for **lightmap textures on
disk** — for several zones that can be many MB of the 30 MB budget. It's
still the right call for web, but budget it as an asset cost. If lightmaps
start eating the budget, the cheaper path is unlit/vertex-lit stylised
materials with baked ambient occlusion, not higher-res lightmaps.

### 4. Rolling your own auth for a save file

`accounts` + `password_hash` means you now own credential security for a
hobby game: hashing (argon2id or bcrypt, never sha256), session tokens,
rate limiting on `/login`, and a breach story if it goes wrong. The spec
calls Neon "a glorified save file" but the account table is the part that
can actually hurt someone, because people reuse passwords.

Cheaper options, in order of preference:

1. **No accounts.** A random 128-bit save ID generated client-side,
   stored in `localStorage`, used as the row key. Zero PII, zero passwords.
   A "transfer save" flow is just showing the user their ID.
2. **OAuth** (Google/Discord) — someone else owns the credentials.
3. Username + password, if you genuinely want it — then argon2id, a real
   JWT library, and rate limiting are not optional.

Whatever you pick: `/save` must **cap the blob size** (say 256 KB) and
verify the slot belongs to the caller. Otherwise the endpoint is a free
JSON host for anyone who finds it.

### 5. Render's free tier cold-starts

A sleeping free-tier web service takes tens of seconds to wake. The first
`/login` of the day will look like the game is broken. Either budget for
the paid tier, or make login non-blocking: boot straight into the game off
a local save and sync to the cloud in the background.

---

## Design gap: this is Pokémon, not Persona

The spec says "Persona-style" but the only weakness mechanic listed is a
damage multiplier. That's the Pokémon model. What makes Persona's combat
feel different is that hitting a weakness **changes the turn economy** —
One More / press-turn grants an extra action, so scouting a weakness
converts into tempo, not just a bigger number.

It's cheap: one bool in the turn state machine, "did this action hit a
weakness and has this actor already taken a free turn". It's also the
single highest-leverage decision in the whole combat design, because it's
what makes the type chart worth learning instead of worth memorising once.

Decide this **before** step 3 (the hardcoded-enemy combat loop), because
retrofitting it into a finished state machine is miserable.

---

## Smaller things

- **`.tres` or `.json`, pick one.** The spec says "either" twice, which is
  exactly how a project ends up with both and a loader for each.
  Recommendation: **`.tres` typed `Resource`s**. You get editor UI, typed
  `@export` fields, and load-time validation instead of runtime
  `KeyError`-equivalents. Keep `.json` for dialogue only, where the content
  is long-form text and diffs matter.
- **`AudioManager` never appears in the build order.** Neither does UI /
  menus, nor the dialogue system, despite `dialogue/*.json` being in the
  structure. Combat UI in particular is not a small job and is currently
  invisible in the plan.
- **Nothing says how overworld state survives the battle swap.** "Never run
  battle inside the overworld" is right, but the spec should state that
  player position / zone state is written to `GameState` before the swap
  and restored after, or you will lose it the first time you unload.
- **"Godot 4.7 (mainline)" is a risk, not a choice.** Building a months-long
  project on an unreleased branch means engine regressions become your
  bugs. Pin to the latest stable release and upgrade deliberately. (Also
  note the spec pins the WebGPU fork to 4.6.2 — so the fork bonus path and
  the main path are already on different engine versions.)
- **Web means phones.** A browser link gets opened on a phone, and a
  `CharacterBody3D` + `SpringArm3D` with keyboard input is unplayable
  there. Either add touch controls, or put "desktop browser" on the page
  and accept the bounce rate.
- **Client-authoritative saves are forgeable.** Fine for single-player —
  just don't add a leaderboard later and expect it to mean anything.
