# ROADMAP.md — Build Order

Build **one phase at a time**. Each has a detailed spec in `docs/phases/`. Do not start a
phase until the previous one runs and I've confirmed it. Tick boxes as we go.

| # | Phase | Spec file | Status |
|---|-------|-----------|--------|
| 0 | Project setup & pixel-perfect config | `phase00_setup.md` | ☑ |
| 1 | Player movement + directional animation | `phase01_player.md` | ☑ |
| 2 | Island world, tiles, camera, Y-sort | `phase02_world.md` | ☑ |
| 3 | Day/night cycle + warmth stat | `phase03_daynight.md` | ☑ |
| 4 | Campfire + wood-pile fuel mechanic | `phase04_campfire.md` | ☑ |
| 5 | Resource nodes + harvesting juice | `phase05_resources.md` | ☐ |
| 6 | Inventory (data-driven items) | `phase06_inventory.md` | ☐ |
| 7 | Crafting tree | `phase07_crafting.md` | ☐ |
| 8 | Grid base building + interiors | `phase08_building.md` | ☐ |
| 9 | Passive animals + hunting | `phase09_animals.md` | ☐ |
| 10 | Save/load + polish pass | `phase10_polish.md` | ☐ |

## Dependency notes
- Phase 6 (Inventory) is a soft prerequisite for 5, 7, 9 to be *meaningful*, but 5 can drop
  items into a placeholder inventory first. If you'd rather, swap 5 and 6 — your call at the time.
- Phases 3 and 4 pair tightly (warmth ↔ campfire). Do 3 then 4 back to back.
- Don't gold-plate early phases. "Runnable and correct" beats "feature-complete" until Phase 10.

## The "vertical slice" milestone
After Phase 5 you should have: a character walking a Y-sorted island, day turning to night,
a campfire you feed wood to for warmth, and trees/bushes you can harvest with juice. That's the
cozy core loop — a great point to stop, play, and feel whether it's fun before adding depth.
