class_name ResolvedChunk
extends ResolvedWorld

## Chunk-scoped extension of ResolvedWorld. All inherited fields remain value
## data and can be consumed by the existing diff, transition, and scene builders.
var coord: Vector2i = Vector2i.ZERO
var revision: int = 0
var bounds: Rect2:
	get:
		return world_bounds
	set(value):
		world_bounds = value
