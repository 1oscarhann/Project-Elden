# CREDITS

## Art

Art assets by CraftPix.net (free licence — attribution required):

- Base 4-Direction Male Character (pack 555940)
- Top-Down Hunt Animals Pixel Sprite Pack (pack 789196) — hare, deer and black grouse
- Top-Down Trees Pixel Art (pack 385863)
- Top-Down Bushes Pixel Art (pack 141354)
- 2D Top-Down Pixel Dungeon Asset Pack (pack 169442) — campfire flame only
- Item/UI icon sheets (CraftPix)
- Basic Pixel Art UI for RPG (pack 255216) — panels, buttons, slots and bars only

https://craftpix.net


## Audio

**All sound and music in this game is original, generated procedurally** by
`tools/build_audio.gd` and written to `assets/audio/*.res`. Nothing is sampled, sourced or
licensed from anyone — footsteps, the chop, the pickup chime, the fire crackle, the surf and
cricket ambiences and the theme are all synthesised from noise and sine waves. There is
therefore **no audio attribution to give and no audio licence to honour**, and regenerating
the lot is one command:

    godot --headless --path . --script res://tools/build_audio.gd


## Engine

Built with [Godot Engine](https://godotengine.org) (MIT licence).

## Terrain, buildings and furniture — Sprout Lands

Assets — From: **Sprout Lands** — By: **Cup Nooble**
<https://cupnooble.carrd.co>

`assets/tiles/sprout_lands/` and the terrain atlas built from it are from the Sprout Lands
Basic pack, as are the Phase 8 building art — `assets/objects/hut.png`
(`Free_Chicken_House`), `assets/objects/sprout_furniture.png` (`Basic_Furniture`),
`assets/objects/sprout_fences.png` (`Fences`) and the interior tileset built from
`Wooden_House_Walls_Tilset`. Some of the assets in this project are made by Cup Nooble; the pack's licensing
terms are reproduced here as that licence requires for open-source projects:

- The assets may be modified. (We darken the grass sheet for woodland and luminance-remap it
  onto sand's hue for the beach; see `tools/build_terrain_atlas.gd`.)
- **Usable in non-commercial projects only.** Anything to do with NFTs or AI training is not allowed.
- The asset pack itself may not be redistributed or resold, even slightly modified. Redistributing
  a project made with the assets — including open source — is allowed, with this note.
- Credit is required: **Cup Nooble**.

> ⚠️ **This makes the project non-commercial.** The CraftPix packs above permit commercial use;
> Sprout Lands does not. Replace these tiles before ever selling anything.
