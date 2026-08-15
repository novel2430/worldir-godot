class_name ChunkBoundaryConstraints
extends Resource

const DIRECTIONS: Array[String] = ["north", "south", "east", "west"]

var edges: Dictionary = {
	"north": {},
	"south": {},
	"east": {},
	"west": {},
}

func set_edge(direction: String, data: Dictionary) -> void:
	assert(direction in DIRECTIONS)
	edges[direction] = data.duplicate(true)

func get_edge(direction: String) -> Dictionary:
	if not direction in DIRECTIONS:
		return {}
	return (edges.get(direction, {}) as Dictionary).duplicate(true)

func set_terrain_heights(direction: String, heights: PackedFloat32Array) -> void:
	var data: Dictionary = edges.get(direction, {}).duplicate(true)
	data["terrain_heights"] = heights.duplicate()
	edges[direction] = data

func terrain_heights(direction: String) -> PackedFloat32Array:
	var value: Variant = (edges.get(direction, {}) as Dictionary).get(
		"terrain_heights",
		PackedFloat32Array()
	)
	return value.duplicate() if value is PackedFloat32Array else PackedFloat32Array()

func add_road_exit(direction: String, road_exit: Dictionary) -> void:
	var data: Dictionary = edges.get(direction, {}).duplicate(true)
	var exits: Array = (data.get("road_exits", []) as Array).duplicate(true)
	exits.append(road_exit.duplicate(true))
	data["road_exits"] = exits
	edges[direction] = data

func road_exits(direction: String) -> Array:
	return ((edges.get(direction, {}) as Dictionary).get("road_exits", []) as Array).duplicate(true)

func is_empty() -> bool:
	for direction in DIRECTIONS:
		if not (edges.get(direction, {}) as Dictionary).is_empty():
			return false
	return true

func duplicate_constraints() -> ChunkBoundaryConstraints:
	var copy := ChunkBoundaryConstraints.new()
	for direction in DIRECTIONS:
		copy.set_edge(direction, get_edge(direction))
	return copy

func to_value() -> Dictionary:
	var result := {}
	for direction in DIRECTIONS:
		var heights: Array = []
		for height in terrain_heights(direction):
			heights.append(float(height))
		var exits: Array = road_exits(direction).duplicate(true)
		exits.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.get("id", "")) < String(b.get("id", "")))
		result[direction] = {"terrain_heights": heights, "road_exits": exits}
	return result
