class_name ChunkMath
extends RefCounted

const CHUNK_SIZE_M := 160.0
const ACTIVE_RADIUS := 1

static func world_to_chunk(world_position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / CHUNK_SIZE_M)),
		int(floor(world_position.z / CHUNK_SIZE_M))
	)

static func chunk_origin(coord: Vector2i) -> Vector2:
	return Vector2(float(coord.x) * CHUNK_SIZE_M, float(coord.y) * CHUNK_SIZE_M)

static func chunk_bounds(coord: Vector2i) -> Rect2:
	return Rect2(chunk_origin(coord), Vector2.ONE * CHUNK_SIZE_M)

static func world_to_chunk_local(world_position: Vector3, coord: Vector2i) -> Vector3:
	var origin := chunk_origin(coord)
	return Vector3(world_position.x - origin.x, world_position.y, world_position.z - origin.y)

static func chunk_local_to_world(local_position: Vector3, coord: Vector2i) -> Vector3:
	var origin := chunk_origin(coord)
	return Vector3(local_position.x + origin.x, local_position.y, local_position.z + origin.y)

static func is_in_active_window(coord: Vector2i, current_coord: Vector2i) -> bool:
	var delta := coord - current_coord
	return absi(delta.x) <= ACTIVE_RADIUS and absi(delta.y) <= ACTIVE_RADIUS

static func active_window_coords(current_coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dz in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
		for dx in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
			result.append(current_coord + Vector2i(dx, dz))
	return result

static func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	var delta := a - b
	return maxi(absi(delta.x), absi(delta.y))
