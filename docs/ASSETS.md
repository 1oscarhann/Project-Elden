# ASSETS.md — Asset Manifest

All packs are **CraftPix free licence → attribution required**. See `CREDITS.md`.

Import note for Godot: after copying PNGs into `res://assets/`, select them and set the
import preset to **2D Pixel** (or set Filter = Nearest, Mipmaps off), then Reimport, so
nothing looks blurry.

---

## 1. Player character — pack `555940`

**Use the `Unarmed / Without_shadow` sheets.** (Sword variants exist but this is a cozy no-combat game.)

- Frame size: **64×64**
- Layout: **grid, 4 rows = directions `down, left, right, up`**, columns = frames
- Sheets → frame counts:
  | Animation | File | Cols × Rows |
  |-----------|------|-------------|
  | Idle  | `Unarmed_Idle_without_shadow.png`  | 12 × 4 |
  | Walk  | `Unarmed_Walk_without_shadow.png`  | 6 × 4 |
  | Run   | `Unarmed_Run_without_shadow.png`   | 8 × 4 |
  | Hurt  | `Unarmed_Hurt_without_shadow.png`  | 5 × 4 |
  | Death | `Unarmed_Death_without_shadow.png` | 7 × 4 |
- `.aseprite` sources are included → you can recolour/edit the character later.
- For a **harvest/chop** animation, use the **Sword attack** sheet's swing (from the Sword set) as a placeholder, or hand-make one later.
- `With_shadow` versions exist if you prefer baked shadows; otherwise use a separate soft-shadow blob under the player.

→ copy to `res://assets/characters/`

## 2. Animals — pack `789196`

Passive/huntable. Each animal has strips: Idle / Walk / Run / Hurt / Death (Grouse also Flight; Boar also Attack).

- Animals: **Fox, Boar, Hare, Deer, Black grouse**
- Frame heights ~96–128px, horizontal strips (verify each in Godot's SpriteFrames editor — counts vary per animal)
- `Without_shadow/` and `With_Shadow/` provided; separate `_Shadow.png` blobs included
- `.aseprite` sources included

→ copy to `res://assets/animals/`
Suggested for a cozy island: **Hare** + **Deer** (skittish, flee) first; Boar later if you want one mildly-defensive animal.

## 3. Trees — pack `385863`

Static 128×128 PNGs, each tree also has a matching shadow PNG in `Trees_shadow/`.

- Island-appropriate: **Palm_tree1/2**, **Fruit_tree1–3**, **Tree1–3**, **Flower_tree1–3**, **Moss_tree1–3**
- Free "harvested" states: **Broken_tree1–7**, **Burned_tree1–3**
- (Snow/Christmas variants exist — ignore for an island.)

→ copy to `res://assets/trees/`

## 4. Bushes — pack `141354`

Static 128×128 PNGs with shadows.

- **3 growth stages** per bush (`_1`, `_2`, `_3`) → use directly as harvest → regrow states
- Types: simple bushes, flower bushes (blue/orange/pink/red), ferns, cactus
- Also contains some broken/burned trees (dupes of the tree pack)

→ copy to `res://assets/bushes/`

## 5. Objects / interiors / fire — dungeon pack `169442`

The utility grab-bag.

- **`fire_animation.png` / `fire_animation2.png`** → the **campfire** flame animation (scale/tint by fuel level)
- `doors_lever_chest_animation.png` → door + chest open/close anims (base building, interiors, storage)
- `walls_floor.png`, `decorative_cracks_*` → interior tiles
- `Water_coasts_animation.png`, `water_detilazation_v2.png` → animated shoreline for the island edge
- `Objects.png` → misc props
- PSD sources included

→ copy to `res://assets/objects/` (and `assets/tiles/` for wall/floor sheets)

## 6. Item / UI icons — 6 sheets (already in `assets/icons/`)

Cohesive CraftPix icon sheets backing the **inventory + crafting** visuals. Each is a grid of
icons on a dark backing — slice into individual `AtlasTexture`s (one region per icon) at import,
or chop into separate PNGs. All share the same warm palette, so they mix cleanly.

| File | Contents | Used for |
|------|----------|----------|
| `icons_food.png` | fruit, veg, mushrooms, cooked dishes | gatherables + **cooked** recipe outputs |
| `icons_raw_meat_bones.png` | raw cuts, poultry, fish, sausage, **bones/antlers/skulls/horns/ribs** | **animal drops** (Phase 9) + bone/antler crafting ingredients |
| `icons_tools_ores.png` | axe, pickaxe, hammer, saw + ores/ingots/gems | tools in the **crafting tree**; deeper resource web (stone→ingot→gem) |
| `icons_potions_flasks.png` | ~48 bottles/flasks | **crafted consumables** — reframe cozy: warmth tonic, tea/energy, salve, juice/preserves; bottle art doubles as containers |
| `icons_containers_bags.png` | coins, bags, backpacks, chests, barrels, jugs | storage, chests, backpack/inventory upgrades |
| `icons_armour.png` | helmets, chest, gloves, boots (leather/plate/chain) | optional — clothing/warmth gear (e.g. a coat that slows warmth drain) if you add equip slots |

**Cozy reframing note:** no-combat game, so read "potions/armour" as cozy utility, not war gear.
Potions → tonics/teas/preserves. Armour → warm clothing that reduces night warmth-drain.
Bones/antlers → crafting mats and decor, not weapons.

**Loop tie-ins:**
- `icons_raw_meat_bones.png` (raw) + `icons_food.png` (cooked dishes) = the **campfire cooking**
  pair: hunt → raw meat drop → cook at campfire → cooked food. Wire this in Phases 7/9.
- Animal `drops` (Phase 9) can be richer than "meat": e.g. deer → venison + antler + bone;
  hare → small meat + bone. Bones/antlers feed tool/decor recipes.

→ all six already copied to `res://assets/icons/`

---

## Attribution snippet for CREDITS.md

```
Art assets by CraftPix.net (free licence — attribution required):
- Base 4-Direction Male Character (pack 555940)
- Top-Down Hunt Animals Pixel Sprite Pack (pack 789196)
- Top-Down Trees Pixel Art (pack 385863)
- Top-Down Bushes Pixel Art (pack 141354)
- 2D Top-Down Pixel Dungeon Asset Pack (pack 169442)
- Item/UI icon sheets (CraftPix)
https://craftpix.net
```
