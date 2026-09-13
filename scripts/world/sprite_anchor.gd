class_name SpriteAnchor
extends RefCounted

## Works out where a sprite's art actually sits inside its texture, so the node
## origin can be put on the art's BASE — which is the point Y-sorting compares.
##
## Measured from the real alpha bounds rather than hardcoded per texture, so new
## art dropped into assets/ anchors correctly with no constants to maintain.
## Results are cached because get_image() is not cheap.

static var _cache: Dictionary = {}


## Offset for a centred Sprite2D that puts the bottom of the art on the origin.
static func base_offset(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	if _cache.has(texture):
		return _cache[texture]
	var image := texture.get_image()
	var used := image.get_used_rect()
	var offset := Vector2(0.0, float(image.get_height()) * 0.5 - float(used.end.y))
	_cache[texture] = offset
	return offset


## World-space rect a centred Sprite2D with that offset would occupy.
static func world_rect(texture: Texture2D, position: Vector2, scale: float = 1.0) -> Rect2:
	var size := Vector2(texture.get_size()) * scale
	return Rect2(position + base_offset(texture) * scale - size * 0.5, size)
