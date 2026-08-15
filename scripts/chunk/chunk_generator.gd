class_name ChunkGenerator
extends RefCounted

const EDGE_BLEND_SAMPLES := 8
const ROAD_APPROACH_M := 12.0
const ROAD_TERMINATION_M := 30.0
const INSTANCE_SURFACE_OFFSET := 0.02

var prototype_catalog: PrototypeCatalog = null

func _init(catalog: PrototypeCatalog = null) -> void:
	prototype_catalog = catalog

func configure(catalog: PrototypeCatalog) -> void:
	prototype_catalog = catalog

func generate_chunk(
	coord: Vector2i,
	world_ir: Dictionary,
	ir_revision: int,
	world_seed: int,
	boundary_constraints: ChunkBoundaryConstraints = null,
	generation_overrides: Dictionary = {}
) -> ResolvedChunk:
	var chunk := ResolvedChunk.new()
	chunk.coord = coord
	chunk.bounds = ChunkMath.chunk_bounds(coord)
	chunk.world_bounds = chunk.bounds
	chunk.revision = ir_revision
	chunk.seed = world_seed
	chunk.realization_seed = _chunk_seed(world_seed, coord)
	if prototype_catalog == null:
		chunk.errors.append("ChunkGenerator requires a PrototypeCatalog")
		return chunk

	var constraints := (
		boundary_constraints
		if boundary_constraints != null
		else ChunkBoundaryConstraints.new()
	)
	chunk.generation_constraints = constraints.duplicate_constraints()
	# Overrides are transaction-local value data. Never retain them on the
	# generator or write them back into World IR/WorldState.
	var runtime_bindings: Array = []
	var spatial_payloads: Dictionary = {}
	var binding_value: Variant = generation_overrides.get("runtime_bindings", [])
	var payload_value: Variant = generation_overrides.get("spatial_payloads", {})
	if binding_value is Array:
		runtime_bindings = binding_value.duplicate(true)
	if payload_value is Dictionary:
		spatial_payloads = payload_value.duplicate(true)
	var interpreted_ir := _interpret_world_ir(
		world_ir, coord, generation_overrides, runtime_bindings
	)
	var backend := WorldBackend.new()
	var lowered := backend.lower(
		interpreted_ir,
		prototype_catalog,
		world_seed,
		runtime_bindings,
		spatial_payloads,
		chunk.bounds,
		chunk.realization_seed
	)
	chunk.absorb_world(lowered)
	chunk.coord = coord
	chunk.bounds = lowered.world_bounds
	chunk.revision = ir_revision
	if not chunk.errors.is_empty():
		return chunk

	_normalize_ir_network_edges(chunk, interpreted_ir)
	_apply_boundary_road_constraints(chunk, constraints)
	_filter_population_ownership(chunk)

	# Network endpoints and discrete-object filtering affect grading, so rebuild
	# the terrain from the final Chunk-local resolved geometry before mounting.
	chunk.terrain = backend.terrain_resolver.resolve(chunk, prototype_catalog)
	_stabilize_terrain_edges(chunk, constraints, world_ir)
	backend.terrain_resolver.conform_world(chunk)
	_rebuild_dressing(chunk, backend)
	_scope_instance_ids(chunk)
	chunk.boundary_summary = _boundary_summary(constraints)
	return chunk

func _interpret_world_ir(
	world_ir: Dictionary,
	coord: Vector2i,
	overrides: Dictionary,
	runtime_bindings: Array
) -> Dictionary:
	var result := world_ir.duplicate(true)
	var removed_object_ids := {}
	var regions: Array = []
	for region: Dictionary in result.get("regions", []):
		var region_id := String(region.get("id", ""))
		var semantic_type := String(region.get("type", ""))
		if semantic_type in ["graveyard"]:
			if coord != _object_owner_coord(region_id, coord, overrides, runtime_bindings):
				removed_object_ids[region_id] = true
				continue
		elif not _globalize_region_placement(region, coord):
			removed_object_ids[region_id] = true
			continue
		regions.append(region)
	result["regions"] = regions

	var entities: Array = []
	for entity: Dictionary in result.get("entities", []):
		var entity_id := String(entity.get("id", ""))
		if coord == _object_owner_coord(entity_id, coord, overrides, runtime_bindings):
			entities.append(entity)
		elif not entity_id.is_empty():
			removed_object_ids[entity_id] = true
	result["entities"] = entities

	_prune_removed_dependency_closure(result, removed_object_ids)
	return result

func _prune_removed_dependency_closure(
	world_ir: Dictionary,
	removed_object_ids: Dictionary
) -> void:
	# Chunk-local directional/ownership pruning must preserve a closed semantic
	# graph. Otherwise the Backend sees a valid global relation whose target was
	# removed only for this Chunk and may fall back to an unrelated local center.
	var collection_names: Array[String] = [
		"regions",
		"networks",
		"entities",
		"distributions",
	]
	var changed := true
	while changed:
		changed = false
		for collection_name: String in collection_names:
			for item: Dictionary in world_ir.get(collection_name, []):
				var object_id := String(item.get("id", ""))
				if object_id.is_empty() or removed_object_ids.has(object_id):
					continue
				if _depends_on_removed_object(item, removed_object_ids):
					removed_object_ids[object_id] = true
					changed = true

	for collection_name: String in collection_names:
		var retained: Array = []
		for item: Dictionary in world_ir.get(collection_name, []):
			if not removed_object_ids.has(String(item.get("id", ""))):
				retained.append(item)
		world_ir[collection_name] = retained

func _depends_on_removed_object(
	item: Dictionary,
	removed_object_ids: Dictionary
) -> bool:
	var placement: Dictionary = item.get("placement", {})
	for relation: Dictionary in placement.get("relations", []):
		if removed_object_ids.has(String(relation.get("target", ""))):
			return true

	# Network topology tokens may also name semantic objects rather than world
	# anchors. Only a token matching an object removed above is a dependency.
	var topology: Dictionary = item.get("topology", {})
	for endpoint_name: String in ["from", "to"]:
		if removed_object_ids.has(String(topology.get(endpoint_name, ""))):
			return true
	for via_token: Variant in topology.get("via", []):
		if removed_object_ids.has(String(via_token)):
			return true

	# Gradient selectors carry the same hard semantic reference as Placement
	# relations. Keeping a selector whose target was pruned would reintroduce the
	# same center fallback through DistributionLowerer.
	var population: Dictionary = item.get("population", {})
	var density_profile: Dictionary = population.get("density_profile", {})
	for endpoint_name: String in ["from", "to"]:
		var endpoint: Dictionary = density_profile.get(endpoint_name, {})
		var selector: Dictionary = endpoint.get("selector", {})
		if removed_object_ids.has(String(selector.get("target", ""))):
			return true
	return false

func _object_owner_coord(
	object_id: String,
	transaction_coord: Vector2i,
	overrides: Dictionary,
	runtime_bindings: Array
) -> Vector2i:
	var owner_values: Variant = overrides.get("object_owner_coords", {})
	if owner_values is Dictionary and owner_values.has(object_id):
		return _coord_value(owner_values[object_id], Vector2i.ZERO)
	for binding: Dictionary in runtime_bindings:
		if String(binding.get("ir_object_id", "")) == object_id:
			return _coord_value(overrides.get("transaction_chunk_coord", transaction_coord), transaction_coord)
	if overrides.has("transaction_chunk_coord"):
		return _coord_value(overrides.transaction_chunk_coord, transaction_coord)
	return Vector2i.ZERO

func _coord_value(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary:
		return Vector2i(int(value.get("x", fallback.x)), int(value.get("y", fallback.y)))
	return fallback

func _globalize_region_placement(region: Dictionary, coord: Vector2i) -> bool:
	var placement: Dictionary = region.get("placement", {})
	var anchor := String(placement.get("anchor", "whole"))
	var axis_value := 0
	var direction := ""
	if anchor in ["west", "east"]:
		axis_value = coord.x
		direction = anchor
	elif anchor in ["north", "south"]:
		axis_value = coord.y
		direction = anchor
	else:
		return true
	if (direction in ["west", "north"] and axis_value > 0) or (
		direction in ["east", "south"] and axis_value < 0
	):
		return false
	if axis_value != 0:
		placement["anchor"] = "whole"
		region["placement"] = placement
	return true

func _normalize_ir_network_edges(chunk: ResolvedChunk, world_ir: Dictionary) -> void:
	var raw_by_id := {}
	for item: Dictionary in world_ir.get("networks", []):
		raw_by_id[String(item.get("id", ""))] = item
	for network: ResolvedNetwork in chunk.networks:
		var raw: Dictionary = raw_by_id.get(network.id, {})
		var topology: Dictionary = raw.get("topology", {})
		var from_token := String(topology.get("from", ""))
		var to_token := String(topology.get("to", ""))
		network.curve_points = _with_boundary_approaches(
			network.curve_points,
			from_token,
			to_token,
			chunk.bounds
		)

func _with_boundary_approaches(
	points: PackedVector3Array,
	from_token: String,
	to_token: String,
	bounds: Rect2
) -> PackedVector3Array:
	if points.size() < 2:
		return points
	var result: Array[Vector3] = []
	var from_edge := _anchor_edge_point(from_token, bounds)
	var to_edge := _anchor_edge_point(to_token, bounds)
	if from_edge != Vector2.INF:
		var inward := _edge_inward(from_token)
		result.append(Vector3(from_edge.x, 0.08, from_edge.y))
		result.append(Vector3(
			from_edge.x + inward.x * ROAD_APPROACH_M,
			0.08,
			from_edge.y + inward.y * ROAD_APPROACH_M
		))
	else:
		result.append(points[0])

	for index in range(1, points.size() - 1):
		var point := points[index]
		if result[-1].distance_to(point) > 0.1:
			result.append(point)

	if to_edge != Vector2.INF:
		var inward := _edge_inward(to_token)
		var approach := Vector3(
			to_edge.x + inward.x * ROAD_APPROACH_M,
			0.08,
			to_edge.y + inward.y * ROAD_APPROACH_M
		)
		if result[-1].distance_to(approach) > 0.1:
			result.append(approach)
		result.append(Vector3(to_edge.x, 0.08, to_edge.y))
	else:
		if result[-1].distance_to(points[-1]) > 0.1:
			result.append(points[-1])
	return PackedVector3Array(result)

func _apply_boundary_road_constraints(
	chunk: ResolvedChunk,
	constraints: ChunkBoundaryConstraints
) -> void:
	var exits_by_id := {}
	for direction in ChunkBoundaryConstraints.DIRECTIONS:
		for raw_exit: Dictionary in constraints.road_exits(direction):
			var road_id := String(raw_exit.get("id", ""))
			if road_id.is_empty():
				continue
			var value := raw_exit.duplicate(true)
			value["edge"] = direction
			if not exits_by_id.has(road_id):
				exits_by_id[road_id] = []
			(exits_by_id[road_id] as Array).append(value)

	for road_id in exits_by_id.keys():
		var exits: Array = exits_by_id[road_id]
		exits.sort_custom(func(a: Dictionary, b: Dictionary):
			return String(a.get("edge", "")) < String(b.get("edge", ""))
		)
		var network := chunk.find_network(String(road_id))
		if network == null:
			network = _continuation_network(String(road_id), exits, chunk.bounds)
			chunk.networks.append(network)
		else:
			for road_exit: Dictionary in exits:
				_constrain_network_endpoint(network, road_exit, chunk.bounds)

func _continuation_network(
	road_id: String,
	exits: Array,
	bounds: Rect2
) -> ResolvedNetwork:
	var network := ResolvedNetwork.new()
	network.id = road_id
	network.semantic_type = String(exits[0].get("semantic_type", "road"))
	network.surface_kind = network.semantic_type
	network.width = float(exits[0].get("width", 4.2))
	var points: Array[Vector3] = []
	if exits.size() >= 2:
		var first := _exit_point(exits[0], bounds)
		var second := _exit_point(exits[1], bounds)
		var first_inward := _exit_inward(exits[0])
		var second_inward := _exit_inward(exits[1])
		points = [
			Vector3(first.x, 0.08, first.y),
			Vector3(first.x + first_inward.x * ROAD_APPROACH_M, 0.08, first.y + first_inward.y * ROAD_APPROACH_M),
			Vector3(second.x + second_inward.x * ROAD_APPROACH_M, 0.08, second.y + second_inward.y * ROAD_APPROACH_M),
			Vector3(second.x, 0.08, second.y),
		]
	else:
		var edge_point := _exit_point(exits[0], bounds)
		var inward := _exit_inward(exits[0])
		points = [
			Vector3(edge_point.x, 0.08, edge_point.y),
			Vector3(edge_point.x + inward.x * ROAD_APPROACH_M, 0.08, edge_point.y + inward.y * ROAD_APPROACH_M),
			Vector3(edge_point.x + inward.x * ROAD_TERMINATION_M, 0.08, edge_point.y + inward.y * ROAD_TERMINATION_M),
		]
	network.curve_points = PackedVector3Array(points)
	return network

func _constrain_network_endpoint(
	network: ResolvedNetwork,
	road_exit: Dictionary,
	bounds: Rect2
) -> void:
	if network.curve_points.size() < 2:
		return
	var edge_point := _exit_point(road_exit, bounds)
	var point3 := Vector3(edge_point.x, 0.08, edge_point.y)
	var first_distance := Vector2(
		network.curve_points[0].x,
		network.curve_points[0].z
	).distance_squared_to(edge_point)
	var last_distance := Vector2(
		network.curve_points[-1].x,
		network.curve_points[-1].z
	).distance_squared_to(edge_point)
	var inward := _exit_inward(road_exit)
	var approach := Vector3(
		edge_point.x + inward.x * ROAD_APPROACH_M,
		0.08,
		edge_point.y + inward.y * ROAD_APPROACH_M
	)
	if first_distance <= last_distance:
		network.curve_points[0] = point3
		network.curve_points[1] = approach
	else:
		network.curve_points[-1] = point3
		network.curve_points[-2] = approach
	network.width = float(road_exit.get("width", network.width))

func _stabilize_terrain_edges(
	chunk: ResolvedChunk,
	constraints: ChunkBoundaryConstraints,
	world_ir: Dictionary
) -> void:
	if chunk.terrain == null or chunk.terrain.grid_size < 2:
		return
	for direction in ChunkBoundaryConstraints.DIRECTIONS:
		_apply_edge_profile(chunk, direction, constraints.terrain_heights(direction), world_ir)

func _apply_edge_profile(
	chunk: ResolvedChunk,
	direction: String,
	constrained_heights: PackedFloat32Array,
	world_ir: Dictionary
) -> void:
	var terrain: Resource = chunk.terrain
	var grid_size: int = terrain.grid_size
	var sample_count := mini(EDGE_BLEND_SAMPLES, grid_size - 1)
	var step_x: float = terrain.world_bounds.size.x / float(grid_size - 1)
	var step_z: float = terrain.world_bounds.size.y / float(grid_size - 1)
	for depth in range(sample_count + 1):
		var original_weight := smoothstep(0.0, float(sample_count), float(depth))
		for offset in range(grid_size):
			var x_index := offset
			var z_index := depth
			match direction:
				"south": z_index = grid_size - 1 - depth
				"west":
					x_index = depth
					z_index = offset
				"east":
					x_index = grid_size - 1 - depth
					z_index = offset
			var index := z_index * grid_size + x_index
			var point := Vector2(
				terrain.world_bounds.position.x + float(x_index) * step_x,
				terrain.world_bounds.position.y + float(z_index) * step_z
			)
			var edge_target := _global_base_height(point, chunk.seed)
			if constrained_heights.size() == grid_size:
				edge_target = float(constrained_heights[offset])
			var original := float(terrain.heights[index])
			terrain.heights[index] = lerpf(edge_target, original, original_weight)
			var surface_target := _global_surface_mask(point, world_ir)
			terrain.surface_masks[index] = surface_target.lerp(
				terrain.surface_masks[index], original_weight
			)
			var shore_target := surface_target.b
			terrain.shore_wetness[index] = lerpf(
				shore_target, float(terrain.shore_wetness[index]), original_weight
			)

func _global_surface_mask(point: Vector2, world_ir: Dictionary) -> Color:
	var has_forest := false
	var has_coast := false
	for region: Dictionary in world_ir.get("regions", []):
		var semantic_type := String(region.get("type", ""))
		has_forest = has_forest or semantic_type in ["forest", "swamp"]
		has_coast = has_coast or semantic_type == "coast"
	var east_weight := smoothstep(-24.0, 24.0, point.x)
	return Color(
		(1.0 - east_weight) if has_forest else 0.0,
		0.0,
		east_weight if has_coast else 0.0,
		0.0
	)

func _rebuild_dressing(chunk: ResolvedChunk, backend: WorldBackend) -> void:
	chunk.decorations.clear()
	var dressing_solver := PlacementSolver.new()
	dressing_solver.configure(
		chunk.bounds,
		chunk.realization_seed,
		backend.config.near_threshold_m,
		backend.config.far_threshold_m,
		backend.config.along_threshold_m
	)
	for entity: ResolvedEntity in chunk.entities:
		var meta := prototype_catalog.get_metadata(entity.prototype_id)
		var scale := entity.transform.basis.get_scale()
		var visual_footprint: Vector2 = meta.get("visual_footprint", Vector2.ZERO)
		var entity_radius := maxf(
			maxf(visual_footprint.x * scale.x, visual_footprint.y * scale.z) * 0.5,
			float(meta.get("placement_radius", 1.0))
		)
		dressing_solver.register_occupancy(
			Vector2(entity.transform.origin.x, entity.transform.origin.z),
			entity_radius,
			entity.id
		)
	for distribution: ResolvedDistribution in chunk.distributions:
		for instance: Dictionary in distribution.instances:
			var transform: Transform3D = instance.get("transform", Transform3D.IDENTITY)
			dressing_solver.register_occupancy(
				Vector2(transform.origin.x, transform.origin.z),
				float(instance.get("occupancy_radius", 0.35)),
				String(instance.get("id", ""))
			)
	backend.forest_dresser.dress(chunk, prototype_catalog, dressing_solver)
	_conform_decorations(chunk)

func _filter_population_ownership(chunk: ResolvedChunk) -> void:
	for distribution: ResolvedDistribution in chunk.distributions:
		var owned: Array = []
		for instance: Dictionary in distribution.instances:
			var transform: Transform3D = instance.get("transform", Transform3D.IDENTITY)
			if ChunkMath.world_to_chunk(transform.origin) == chunk.coord:
				owned.append(instance)
		distribution.instances = owned

func _scope_instance_ids(chunk: ResolvedChunk) -> void:
	var scope := "@%d_%d" % [chunk.coord.x, chunk.coord.y]
	for distribution: ResolvedDistribution in chunk.distributions:
		for instance: Dictionary in distribution.instances:
			instance["id"] = "%s%s:%s" % [
				distribution.id,
				scope,
				_instance_suffix(String(instance.get("id", ""))),
			]
	for decoration: ResolvedDecoration in chunk.decorations:
		for instance: Dictionary in decoration.instances:
			instance["id"] = "%s%s:%s" % [
				decoration.id,
				scope,
				_instance_suffix(String(instance.get("id", ""))),
			]

func _instance_suffix(value: String) -> String:
	var separator := value.rfind(":")
	return value.substr(separator + 1) if separator >= 0 else value

func _conform_decorations(chunk: ResolvedChunk) -> void:
	if chunk.terrain == null:
		return
	for decoration: ResolvedDecoration in chunk.decorations:
		for instance: Dictionary in decoration.instances:
			var transform: Transform3D = instance.get("transform", Transform3D.IDENTITY)
			transform.origin.y = chunk.terrain.sample_height(
				Vector2(transform.origin.x, transform.origin.z)
			) + INSTANCE_SURFACE_OFFSET
			instance["transform"] = transform

func _boundary_summary(constraints: ChunkBoundaryConstraints) -> Dictionary:
	var result := {}
	for direction in ChunkBoundaryConstraints.DIRECTIONS:
		result[direction] = {
			"terrain_sample_count": constraints.terrain_heights(direction).size(),
			"road_exit_count": constraints.road_exits(direction).size(),
		}
	return result

func _anchor_edge_point(anchor: String, bounds: Rect2) -> Vector2:
	var center := bounds.get_center()
	match anchor:
		"north": return Vector2(center.x, bounds.position.y)
		"south": return Vector2(center.x, bounds.end.y)
		"west": return Vector2(bounds.position.x, center.y)
		"east": return Vector2(bounds.end.x, center.y)
	return Vector2.INF

func _edge_inward(edge: String) -> Vector2:
	match edge:
		"north": return Vector2(0.0, 1.0)
		"south": return Vector2(0.0, -1.0)
		"west": return Vector2(1.0, 0.0)
		"east": return Vector2(-1.0, 0.0)
	return Vector2.ZERO

func _exit_point(road_exit: Dictionary, bounds: Rect2) -> Vector2:
	var value: Variant = road_exit.get("position", Vector2.INF)
	if value is Vector2 and value != Vector2.INF:
		return value
	return _anchor_edge_point(String(road_exit.get("edge", "")), bounds)

func _exit_inward(road_exit: Dictionary) -> Vector2:
	var edge := String(road_exit.get("edge", ""))
	var fallback := _edge_inward(edge)
	var value: Variant = road_exit.get("tangent", fallback)
	if not value is Vector2 or value.is_zero_approx():
		return fallback
	var tangent: Vector2 = value.normalized()
	return tangent if tangent.dot(fallback) >= 0.0 else -tangent

func _global_base_height(point: Vector2, seed_value: int) -> float:
	var phase := float(abs(seed_value) % 100003) / 100003.0 * TAU
	var broad := (
		sin(point.x * 0.027 + phase) * 1.05
		+ cos(point.y * 0.023 - phase * 0.73) * 0.85
		+ sin((point.x + point.y) * 0.014 + phase * 1.41) * 0.65
	)
	var detail := (
		sin(point.x * 0.071 - point.y * 0.043 + phase * 2.1) * 0.32
		+ cos(point.x * 0.049 + point.y * 0.061 - phase) * 0.24
	)
	return clampf(broad + detail, -2.8, 2.8)

func _chunk_seed(world_seed: int, coord: Vector2i) -> int:
	return (
		world_seed
		^ int(coord.x * 73856093)
		^ int(coord.y * 19349663)
		^ 0x4348554E
	)
