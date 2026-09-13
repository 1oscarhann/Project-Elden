class_name HarvestableData
extends Resource

## Everything that makes one kind of harvestable node what it is.
##
## `harvestable.gd` reads this and nothing else, so a new tree, bush or rock is
## a new .tres file in resources/harvestables/ — no systems code changes.

@export var id := ""
@export var display_name := ""

@export_group("Appearance")
## Shown when fully grown. Ignored when growth_stages is filled in.
@export var sprite: Texture2D
## Shown once harvested — a stump, a broken trunk, a smaller rock.
@export var harvested_sprite: Texture2D
## Alternative looks for the same kind of node. When non-empty each spawned node
## picks one, so a wood of "leafy trees" is not the same sprite 90 times. The
## pack ships each species at three sizes, which also gives a natural spread of
## big trees and saplings. Falls back to `sprite` when empty.
@export var sprite_variants: Array[Texture2D] = []
## Same idea for the harvested look. Falls back to `harvested_sprite`.
@export var harvested_variants: Array[Texture2D] = []
## Optional regrowth stages, SMALLEST FIRST. When set these replace the simple
## full/harvested pair: harvesting drops the node to stage 0 and it grows back
## up one stage per regrow_seconds. The CraftPix bushes ship as three sizes,
## which is exactly this.
@export var growth_stages: Array[Texture2D] = []

@export_group("Harvesting")
@export var drops: Array[HarvestDrop] = []
## Interactions needed to harvest it once.
@export_range(1, 10) var hits_required := 3
## Seconds to come back — per stage when growth_stages is used.
@export var regrow_seconds := 45.0
## Blocks walking. Trees and rocks should; small bushes should not.
@export var blocks_movement := true

## Draw scale. The CraftPix tree art is ~74px tall against a 16px tile grid,
## which dwarfs the 24px player; scaling it down here keeps the art without
## burying him. Data, so retuning is a .tres edit.
@export_range(0.1, 2.0) var sprite_scale := 1.0

## Colour of the chip/leaf burst when struck — brown for wood, grey for stone.
@export var particle_colour := Color(0.62, 0.45, 0.26)

@export_group("Spawning")
## IslandGenerator.Terrain values this may spawn on.
@export var spawn_terrains: Array[int] = []
## Chance per eligible tile.
@export_range(0.0, 1.0) var spawn_chance := 0.06


func is_staged() -> bool:
	return growth_stages.size() > 1


## The texture shown when fully grown, whichever scheme this node uses.
## A representative fully-grown texture. Used for spawn-time layout tests, so
## it returns the largest variant rather than a random one.
func ready_texture() -> Texture2D:
	if is_staged():
		return growth_stages[growth_stages.size() - 1]
	if not sprite_variants.is_empty():
		return sprite_variants[0]
	return sprite
