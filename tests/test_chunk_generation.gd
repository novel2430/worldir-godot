extends SceneTree

const EPSILON := 0.0001

var catalog: PrototypeCatalog
var world_ir: Dictionary

func _init() -> void:
	catalog = PrototypeCatalog.new()
	root.add_child(catalog)
	world_ir = _fixture_ir()
	_test_same_input_same_output()
	_test_generation_order_independence()
	_test_reload_and_stable_ids()
	_test_terrain_edges()
	_test_road_edges()
	_test_boundary_constraints_are_real_inputs()
	_test_population_ownership_and_discrete_entities()
	_test_generation_overrides_are_transaction_local()
	_test_density_change_preserves_surviving_identity()
	print("Chunk deterministic generation tests passed")
	quit(0)

func _test_same_input_same_output() -> void:
	var generator := ChunkGenerator.new(catalog)
	var first := generator.generate_chunk(Vector2i(0, 0), world_ir, 0, 1337)
	var second := generator.generate_chunk(Vector2i(0, 0), world_ir, 0, 1337)
	assert(first.errors.is_empty())
	assert(second.errors.is_empty())
	assert(first.deterministic_signature() == second.deterministic_signature())

func _test_generation_order_independence() -> void:
	var first_generator := ChunkGenerator.new(catalog)
	var a_then := first_generator.generate_chunk(Vector2i(-1, 2), world_ir, 0, 1337)
	var b_then := first_generator.generate_chunk(Vector2i(4, -3), world_ir, 0, 1337)
	var second_generator := ChunkGenerator.new(catalog)
	var b_first := second_generator.generate_chunk(Vector2i(4, -3), world_ir, 0, 1337)
	var a_second := second_generator.generate_chunk(Vector2i(-1, 2), world_ir, 0, 1337)
	assert(a_then.deterministic_signature() == a_second.deterministic_signature())
	assert(b_then.deterministic_signature() == b_first.deterministic_signature())

func _test_reload_and_stable_ids() -> void:
	var generator := ChunkGenerator.new(catalog)
	var first := generator.generate_chunk(Vector2i(1, 1), world_ir, 0, 1337)
	var first_ids := _population_ids(first)
	first = null
	var reloaded := generator.generate_chunk(Vector2i(1, 1), world_ir, 0, 1337)
	assert(first_ids == _population_ids(reloaded))
	for object_id: String in first_ids:
		assert("@1_1:" in object_id)

func _test_terrain_edges() -> void:
	var generator := ChunkGenerator.new(catalog)
	var west := generator.generate_chunk(Vector2i(0, 0), world_ir, 0, 1337)
	var east := generator.generate_chunk(Vector2i(1, 0), world_ir, 0, 1337)
	var grid_size: int = west.terrain.grid_size
	for row in range(grid_size):
		var west_height: float = west.terrain.heights[row * grid_size + grid_size - 1]
		var east_height: float = east.terrain.heights[row * grid_size]
		assert(absf(west_height - east_height) <= EPSILON)

func _test_road_edges() -> void:
	var generator := ChunkGenerator.new(catalog)
	var south := generator.generate_chunk(Vector2i(0, 0), world_ir, 0, 1337)
	var north := generator.generate_chunk(Vector2i(0, -1), world_ir, 0, 1337)
	var south_road := south.find_network("main_road")
	var north_road := north.find_network("main_road")
	assert(south_road != null and north_road != null)
	var south_exit: Vector3 = south_road.curve_points[-1]
	var north_exit: Vector3 = north_road.curve_points[0]
	assert(Vector2(south_exit.x, south_exit.z).distance_to(Vector2(north_exit.x, north_exit.z)) <= EPSILON)
	assert(absf(south_road.width - north_road.width) <= EPSILON)
	var south_tangent := (south_road.curve_points[-1] - south_road.curve_points[-2]).normalized()
	var north_tangent := (north_road.curve_points[1] - north_road.curve_points[0]).normalized()
	assert(south_tangent.dot(north_tangent) > 0.999)

func _test_boundary_constraints_are_real_inputs() -> void:
	var generator := ChunkGenerator.new(catalog)
	var source := generator.generate_chunk(Vector2i(0, 0), world_ir, 0, 1337)
	var grid_size: int = source.terrain.grid_size
	var north_heights := PackedFloat32Array()
	north_heights.resize(grid_size)
	for column in range(grid_size):
		north_heights[column] = source.terrain.heights[column]
	var source_road := source.find_network("main_road")
	var source_exit: Vector3 = source_road.curve_points[-1]
	var constraints := ChunkBoundaryConstraints.new()
	constraints.set_terrain_heights("south", north_heights)
	constraints.add_road_exit("south", {
		"id": source_road.id,
		"semantic_type": source_road.semantic_type,
		"position": Vector2(source_exit.x, source_exit.z),
		"tangent": Vector2(0.0, -1.0),
		"width": source_road.width,
	})
	var ir_without_roads := world_ir.duplicate(true)
	ir_without_roads["networks"] = []
	ir_without_roads["entities"] = []
	ir_without_roads["distributions"] = []
	var constrained := generator.generate_chunk(
		Vector2i(0, -1),
		ir_without_roads,
		1,
		1337,
		constraints
	)
	assert(constrained.errors.is_empty())
	assert(constrained.boundary_summary["south"]["terrain_sample_count"] == grid_size)
	assert(constrained.find_network("main_road") != null)
	for column in range(grid_size):
		var constrained_height: float = constrained.terrain.heights[(grid_size - 1) * grid_size + column]
		assert(absf(constrained_height - north_heights[column]) <= EPSILON)

func _test_population_ownership_and_discrete_entities() -> void:
	var generator := ChunkGenerator.new(catalog)
	var origin := generator.generate_chunk(Vector2i(0, 0), world_ir, 0, 1337)
	var future := generator.generate_chunk(Vector2i(2, -2), world_ir, 0, 1337)
	assert(not origin.entities.is_empty())
	assert(future.entities.is_empty())
	for distribution: ResolvedDistribution in future.distributions:
		for instance: Dictionary in distribution.instances:
			var transform: Transform3D = instance["transform"]
			assert(ChunkMath.world_to_chunk(transform.origin) == future.coord)

func _test_generation_overrides_are_transaction_local() -> void:
	var generator := ChunkGenerator.new(catalog)
	var binding_ir := {
		"regions": [{"id": "bound_region", "type": "forest"}],
		"networks": [], "entities": [], "distributions": [],
	}
	var other_before := generator.generate_chunk(Vector2i(1, 0), binding_ir, 1, 1337)
	var overrides := {
		"runtime_bindings": [{
			"ir_object_id": "bound_region",
			"runtime_fact_id": "target_area",
			"placement": "inside",
		}],
		"spatial_payloads": {
			"target_area": {"aabb2": {"x": 24.0, "z": 30.0, "w": 28.0, "d": 22.0}},
		},
	}
	var target := generator.generate_chunk(
		Vector2i.ZERO, binding_ir, 1, 1337, null, overrides
	)
	var other_after := generator.generate_chunk(Vector2i(1, 0), binding_ir, 1, 1337)
	assert(target.errors.is_empty())
	assert(other_before.deterministic_signature() == other_after.deterministic_signature())
	var region := target.find_region("bound_region")
	assert(region != null)
	assert(_polygon_aabb(region.polygon).is_equal_approx(Rect2(24.0, 30.0, 28.0, 22.0)))

func _test_density_change_preserves_surviving_identity() -> void:
	var generator := ChunkGenerator.new(catalog)
	var dense_ir := _population_ir(8)
	var sparse_ir := _population_ir(3)
	var dense := generator.generate_chunk(Vector2i.ZERO, dense_ir, 0, 1337)
	var sparse := generator.generate_chunk(Vector2i.ZERO, sparse_ir, 1, 1337)
	assert(dense.errors.is_empty() and sparse.errors.is_empty())
	var dense_by_id := _population_transforms(dense)
	var sparse_by_id := _population_transforms(sparse)
	assert(sparse_by_id.size() == 3)
	for object_id: String in sparse_by_id:
		assert(dense_by_id.has(object_id))
		assert((dense_by_id[object_id] as Transform3D).is_equal_approx(sparse_by_id[object_id]))

func _population_ids(chunk: ResolvedChunk) -> Array[String]:
	var result: Array[String] = []
	for distribution: ResolvedDistribution in chunk.distributions:
		for instance: Dictionary in distribution.instances:
			result.append(String(instance.get("id", "")))
	result.sort()
	return result

func _population_transforms(chunk: ResolvedChunk) -> Dictionary:
	var result := {}
	for distribution: ResolvedDistribution in chunk.distributions:
		for instance: Dictionary in distribution.instances:
			result[String(instance.get("id", ""))] = instance.get("transform", Transform3D.IDENTITY)
	return result

func _population_ir(count: int) -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [], "entities": [],
		"distributions": [{
			"id": "trees", "type": "tree",
			"placement": {"relations": [{"type": "inside", "target": "forest"}]},
			"population": {
				"amount": {"mode": "count", "value": count},
				"arrangement": {"type": "uniform"},
			},
		}],
	}

func _polygon_aabb(polygon: PackedVector2Array) -> Rect2:
	var min_point := polygon[0]
	var max_point := polygon[0]
	for point: Vector2 in polygon:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)

func _fixture_ir() -> Dictionary:
	var file := FileAccess.open("res://data/fixtures/coastal_town_initial.json", FileAccess.READ)
	assert(file != null)
	var result: Variant = JSON.parse_string(file.get_as_text())
	assert(typeof(result) == TYPE_DICTIONARY)
	return (result as Dictionary)["world_ir"].duplicate(true)
