class_name RevisionBoundaryBlend
extends RefCounted

const TRANSITION_BAND_M := 16.0
const INSTANCE_ALPHA_FEATHER := 0.08
const ENVIRONMENT_TYPES := [
	"tree",
	"bush",
	"grass",
	"dead_tree",
	"stump",
	"plant",
	"flower",
	"rock",
	"rocks",
	"stone",
	"shrub",
	"reed",
	"ground_cover",
]

var last_plan: Dictionary = {}

# Produces value data only. It does not mutate ChunkRecord, ResolvedChunk, or
# SceneTree state. resolved_overrides lets a prepared Preview Candidate be
# planned before it is published to its official ChunkRecord.
func build_plan(records: Array, resolved_overrides: Dictionary = {}) -> Dictionary:
	var resolved_by_coord := {}
	var revision_by_coord := {}
	for value in records:
		if not (value is ChunkRecord):
			continue
		var record := value as ChunkRecord
		var resolved: ResolvedChunk = resolved_overrides.get(record.coord, record.resolved_chunk)
		if resolved == null:
			continue
		resolved_by_coord[record.coord] = resolved
		revision_by_coord[record.coord] = resolved.revision

	var pairs: Array = []
	var operations_by_key := {}
	var coords: Array = resolved_by_coord.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	for coord: Vector2i in coords:
		for spec: Dictionary in [
			{"neighbor": coord + Vector2i.RIGHT, "edge": "east", "neighbor_edge": "west"},
			{"neighbor": coord + Vector2i.DOWN, "edge": "south", "neighbor_edge": "north"},
		]:
			var neighbor_coord: Vector2i = spec.neighbor
			if not resolved_by_coord.has(neighbor_coord):
				continue
			if int(revision_by_coord[coord]) == int(revision_by_coord[neighbor_coord]):
				continue
			var pair := _plan_pair(
				coord,
				resolved_by_coord[coord],
				String(spec.edge),
				neighbor_coord,
				resolved_by_coord[neighbor_coord],
				String(spec.neighbor_edge),
				operations_by_key
			)
			pairs.append(pair)

	var operations: Array = operations_by_key.values()
	operations.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a.key) < String(b.key)
	)
	for operation: Dictionary in operations:
		operation.erase("key")
	last_plan = {
		"transition_band_m": TRANSITION_BAND_M,
		"pairs": pairs,
		"operations": operations,
	}
	return last_plan.duplicate(true)

func apply_plan(
	plan: Dictionary,
	chunk_roots: Dictionary,
	scene_overrides: Dictionary = {}
) -> void:
	# Recompute from a neutral visual state so moving the active window or
	# removing a revision boundary cannot leave stale transparency behind.
	for coord_value in chunk_roots.keys():
		var coord: Vector2i = coord_value
		var content := scene_overrides.get(coord) as Node3D
		if content == null:
			var chunk_root := chunk_roots.get(coord) as Node3D
			if chunk_root != null:
				content = chunk_root.get_node_or_null(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
		if content != null:
			_reset_environment_alpha(content)

	for operation: Dictionary in plan.get("operations", []):
		var coord_value: Variant = operation.get("coord")
		if not (coord_value is Vector2i):
			continue
		var coord := coord_value as Vector2i
		var content := scene_overrides.get(coord) as Node3D
		if content == null:
			var chunk_root := chunk_roots.get(coord) as Node3D
			if chunk_root != null:
				content = chunk_root.get_node_or_null(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
		if content == null:
			continue
		var node := content.get_node_or_null(_operation_path(operation)) as Node3D
		if node != null:
			_set_environment_alpha(node, float(operation.get("alpha", 1.0)))

func _plan_pair(
	coord_a: Vector2i,
	chunk_a: ResolvedChunk,
	edge_a: String,
	coord_b: Vector2i,
	chunk_b: ResolvedChunk,
	edge_b: String,
	operations_by_key: Dictionary
) -> Dictionary:
	var instances_a := _environment_instances(chunk_a, edge_a)
	var instances_b := _environment_instances(chunk_b, edge_b)
	var categories := {}
	for category in instances_a.keys():
		categories[category] = true
	for category in instances_b.keys():
		categories[category] = true
	var category_summaries: Array = []
	var sorted_categories: Array = categories.keys()
	sorted_categories.sort()
	for category_value in sorted_categories:
		var category := String(category_value)
		var side_a: Array = instances_a.get(category, [])
		var side_b: Array = instances_b.get(category, [])
		category_summaries.append({
			"semantic_type": category,
			"count_a": side_a.size(),
			"count_b": side_b.size(),
		})
		if side_a.size() == side_b.size():
			continue
		var high_coord := coord_a if side_a.size() > side_b.size() else coord_b
		var high_instances: Array = side_a if side_a.size() > side_b.size() else side_b
		var low_count := mini(side_a.size(), side_b.size())
		var seam_keep_ratio := float(low_count) / float(maxi(high_instances.size(), 1))
		for instance: Dictionary in high_instances:
			var distance := float(instance.distance_to_edge)
			var distance_weight := smoothstep(0.0, TRANSITION_BAND_M, distance)
			var keep_weight := lerpf(seam_keep_ratio, 1.0, distance_weight)
			var rank := _stable_rank(
				"%d,%d|%s|%s|%s"
				% [
					high_coord.x,
					high_coord.y,
					String(instance.layer),
					String(instance.owner_id),
					String(instance.id),
				]
			)
			var alpha := smoothstep(
				rank - INSTANCE_ALPHA_FEATHER,
				rank + INSTANCE_ALPHA_FEATHER,
				keep_weight
			)
			if alpha >= 0.999:
				continue
			var key := "%d,%d|%s|%s|%s" % [
				high_coord.x,
				high_coord.y,
				String(instance.layer),
				String(instance.owner_id),
				String(instance.id),
			]
			var previous_alpha := 1.0
			if operations_by_key.has(key):
				previous_alpha = float((operations_by_key[key] as Dictionary).alpha)
			operations_by_key[key] = {
				"key": key,
				"coord": high_coord,
				"layer": String(instance.layer),
				"owner_id": String(instance.owner_id),
				"id": String(instance.id),
				"semantic_type": category,
				"distance_to_edge_m": distance,
				"alpha": minf(previous_alpha, alpha),
			}
	return {
		"coord_a": coord_a,
		"revision_a": chunk_a.revision,
		"edge_a": edge_a,
		"coord_b": coord_b,
		"revision_b": chunk_b.revision,
		"edge_b": edge_b,
		"categories": category_summaries,
	}

func _environment_instances(chunk: ResolvedChunk, edge: String) -> Dictionary:
	var result := {}
	for distribution: ResolvedDistribution in chunk.distributions:
		var semantic_type := String(distribution.semantic_type)
		if semantic_type not in ENVIRONMENT_TYPES:
			continue
		for instance: Dictionary in distribution.instances:
			_append_instance(result, semantic_type, "Distributions", distribution.id, instance, chunk.bounds, edge)
	for decoration: ResolvedDecoration in chunk.decorations:
		var semantic_type := String(decoration.decoration_type)
		if semantic_type not in ENVIRONMENT_TYPES:
			continue
		for instance: Dictionary in decoration.instances:
			_append_instance(result, semantic_type, "Decorations", decoration.id, instance, chunk.bounds, edge)
	for entity: ResolvedEntity in chunk.entities:
		var semantic_type := String(entity.semantic_type)
		if semantic_type not in ENVIRONMENT_TYPES:
			continue
		_append_instance(result, semantic_type, "Entities", "", {
			"id": entity.id,
			"transform": entity.transform,
		}, chunk.bounds, edge)
	return result

func _append_instance(
	result: Dictionary,
	semantic_type: String,
	layer: String,
	owner_id: String,
	instance: Dictionary,
	bounds: Rect2,
	edge: String
) -> void:
	var transform: Transform3D = instance.get("transform", Transform3D.IDENTITY)
	var point := Vector2(transform.origin.x, transform.origin.z)
	var distance := _distance_to_edge(point, bounds, edge)
	if distance < -0.001 or distance > TRANSITION_BAND_M:
		return
	if not result.has(semantic_type):
		result[semantic_type] = []
	(result[semantic_type] as Array).append({
		"layer": layer,
		"owner_id": owner_id,
		"id": String(instance.get("id", "")),
		"distance_to_edge": maxf(0.0, distance),
	})

func _distance_to_edge(point: Vector2, bounds: Rect2, edge: String) -> float:
	match edge:
		"north": return point.y - bounds.position.y
		"south": return bounds.end.y - point.y
		"west": return point.x - bounds.position.x
		"east": return bounds.end.x - point.x
	return INF

func _stable_rank(value: String) -> float:
	var hash_value := 2166136261
	for byte in value.to_utf8_buffer():
		hash_value = int((hash_value ^ int(byte)) * 16777619) & 0x7fffffff
	return float(hash_value % 1000003) / 1000003.0

func _operation_path(operation: Dictionary) -> NodePath:
	var layer := String(operation.get("layer", ""))
	var owner_id := String(operation.get("owner_id", ""))
	var object_id := _safe_name(String(operation.get("id", "")))
	if owner_id.is_empty():
		return NodePath("%s/%s" % [layer, object_id])
	return NodePath("%s/%s/%s" % [layer, _safe_name(owner_id), object_id])

func _reset_environment_alpha(content: Node3D) -> void:
	for layer_name in ["Entities", "Distributions", "Decorations"]:
		var layer := content.get_node_or_null(layer_name)
		if layer == null:
			continue
		for child in layer.get_children():
			_set_environment_alpha(child, 1.0)

func _set_environment_alpha(root: Node, alpha: float) -> void:
	root.set_meta("revision_boundary_alpha", alpha)
	_set_collision_enabled(root, alpha >= 0.5)
	for geometry in _geometry_instances(root):
		geometry.transparency = 1.0 - alpha
		geometry.set_meta("revision_boundary_target_transparency", 1.0 - alpha)

func _geometry_instances(root: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		result.append(root)
	for child in root.get_children():
		result.append_array(_geometry_instances(child))
	return result

func _set_collision_enabled(root: Node, enabled: bool) -> void:
	if root is CollisionShape3D:
		root.set_deferred("disabled", not enabled)
	for child in root.get_children():
		_set_collision_enabled(child, enabled)

func _safe_name(value: String) -> String:
	return value.replace(":", "_").replace("/", "_")
