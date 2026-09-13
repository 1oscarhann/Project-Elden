class_name AnimalData
extends Resource

## Everything that makes one kind of animal different from another.
##
## Adding an animal is a new .tres plus a SpriteFrames — `animal.gd` never
## learns what a hare is. The spawner reads the terrain and density fields off
## here too, exactly as harvestables do, so where a species lives is data.

@export var id := ""
@export var display_name := ""

@export_group("Look")
@export var sprite_frames: SpriteFrames
## Measured from the sheet's alpha bounds so the feet sit on the node origin —
## that is the point Y-sorting compares. See tools/build_animal_frames.gd.
@export var sprite_offset := Vector2(0, -11)
@export var shadow_scale := Vector2(0.6, 0.6)

@export_group("Movement")
## Pixels per second while ambling between wander points.
@export var move_speed := 22.0
## Pixels per second while fleeing. Should comfortably beat the player's walk
## but not their run, or an animal can never be caught.
@export var flee_speed := 78.0
## How far the animal can see the player, in pixels.
@export var detection_radius := 72.0
## How far a single wander hop may take it from where it is now, in pixels.
@export var wander_range := 96.0
## Seconds to stand still between wander hops, randomised within the pair.
@export var rest_min := 1.5
@export var rest_max := 5.0
## Seconds of running after the player leaves detection before it calms down.
@export var flee_memory := 2.0

@export_group("Hunting")
## Swings needed to bring it down.
@export var hits_required := 2
@export var drops: Array[HarvestDrop] = []
## Tint of the soft puff on a hit. Cozy framing — no gore (spec).
@export var puff_colour := Color(0.85, 0.78, 0.7)

@export_group("Spawning")
## Terrain rows this animal is found on (IslandGenerator.Terrain values).
@export var spawn_terrains: Array[int] = []
## How many of this species the island supports at once.
@export var population := 8
