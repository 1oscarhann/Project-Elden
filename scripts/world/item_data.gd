class_name ItemData
extends Resource

## Everything that makes one kind of item what it is.
##
## Pure data: adding an item to the game is a new .tres in resources/items/ and
## nothing else. ItemDB picks it up at boot and the rest of the game only ever
## refers to it by `id`.

enum Category { MATERIAL, FOOD, TOOL, MISC }

@export var id := ""
@export var display_name := ""
@export var icon: Texture2D
@export_range(1, 999) var max_stack := 99
@export var category := Category.MATERIAL
@export_multiline var description := ""
@export_group("Placement")
## Set on a buildable: what gets instanced into the world when it is placed.
## Items without one simply cannot be placed, so "is this buildable?" is a data
## question rather than a list kept in code.
@export var placed_scene: PackedScene
## Grid footprint in tiles. The hut is 3x3; most things are 1x1.
@export var placed_footprint := Vector2i(1, 1)

## Free-form extras — {"hunger": 12} on a food, {"fuel": 25} on a log. Kept as
## a dictionary so a new kind of item never needs a new field on this class.
@export var stats: Dictionary = {}


func stat(key: String, fallback: float = 0.0) -> float:
	return float(stats.get(key, fallback))


func is_placeable() -> bool:
	return placed_scene != null
