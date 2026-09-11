# Project Elden

A 3rd-person, turn-based single-player RPG in the Pokémon/Persona lineage.
Built in Godot on desktop, shipped to the web.

**Status:** pre-production. Nothing is playable yet.

## Docs

- [`docs/SPEC.md`](docs/SPEC.md) — the spec sheet. Scope, stack, combat design,
  save schema, build order.
- [`docs/REVIEW.md`](docs/REVIEW.md) — technical pushback on the spec.
  Open decisions live at the bottom of `SPEC.md`.

## Layout

```
scenes/                  World.tscn (overworld) and Battle.tscn (combat)
scripts/autoload/        GameState, BattleManager, SaveManager, AudioManager
scripts/combat/          type_chart.gd + damage.gd — the combat identity
data/enemies|moves|items content as data files, not code
data/dialogue/           dialogue as .json
```

## Build order

Do not reorder — see `docs/SPEC.md` §9. Currently at **step 0**: structure only.
Next up is step 1, overworld movement and the 3rd-person camera.
