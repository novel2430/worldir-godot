extends SceneTree

func _init() -> void:
	var dresser := ForestDresser.new()
	_test_forest_edge_profile(dresser)
	_test_network_corridor_profile(dresser)
	_test_building_footprint_scaling(dresser)
	_test_coast_orientation_matrix()
	print("ArtLab visual calibration tests passed")
	quit(0)

func _test_forest_edge_profile(dresser: ForestDresser) -> void:
	var policy := dresser.realization_policy
	var ramp_start := policy.number("dressing.edge_profiles.edge.outer_ramp_start_m", 0.2)
	var ramp_end := policy.number("dressing.edge_profiles.edge.outer_ramp_end_m", 2.5)
	var falloff_start := policy.number("dressing.edge_profiles.edge.interior_falloff_start_m", 8.0)
	var falloff_end := policy.number("dressing.edge_profiles.edge.interior_falloff_end_m", 22.0)
	var boundary := dresser._edge_weight(maxf(0.0, ramp_start - 0.1), "edge")
	var ramp_mid := dresser._edge_weight((ramp_start + ramp_end) * 0.5, "edge")
	var edge_band := dresser._edge_weight((ramp_end + falloff_start) * 0.5, "edge")
	var deep_interior := dresser._edge_weight(falloff_end + 5.0, "edge")
	assert(boundary < ramp_mid)
	assert(ramp_mid < edge_band)
	assert(edge_band > deep_interior)
	assert(is_equal_approx(boundary, deep_interior))

func _test_network_corridor_profile(dresser: ForestDresser) -> void:
	var road := ResolvedNetwork.new()
	road.id = "road"
	road.semantic_type = "road"
	road.width = 4.0
	road.curve_points = PackedVector3Array([
		Vector3(-30.0, 0.0, 0.0),
		Vector3(30.0, 0.0, 0.0),
	])
	var solver := PlacementSolver.new()
	solver.configure(Rect2(-40.0, -40.0, 80.0, 80.0), 7)
	var radius := 0.2
	var hard_clearance := 0.55
	var outer_extra := dresser.realization_policy.number(
		"dressing.network_corridors.road.outer_extra_width_m",
		5.2
	)
	var inner_distance := road.width * 0.5 + radius + hard_clearance
	var outer_distance := road.width * 0.5 + radius + outer_extra
	var inner := dresser._network_corridor_weight(
		Vector2(0.0, inner_distance), radius, hard_clearance, "grass", [road], solver
	)
	var middle := dresser._network_corridor_weight(
		Vector2(0.0, (inner_distance + outer_distance) * 0.5),
		radius,
		hard_clearance,
		"grass",
		[road],
		solver
	)
	var outside := dresser._network_corridor_weight(
		Vector2(0.0, outer_distance + 1.0), radius, hard_clearance, "grass", [road], solver
	)
	assert(inner < middle)
	assert(middle < outside)
	assert(is_equal_approx(outside, 1.0))

func _test_building_footprint_scaling(dresser: ForestDresser) -> void:
	var sample_point := Vector2(10.0, 0.0)
	var small := dresser._building_clearing_weight(
		sample_point, "grass", [{"position": Vector2.ZERO, "radius": 1.0}]
	)
	var medium := dresser._building_clearing_weight(
		sample_point, "grass", [{"position": Vector2.ZERO, "radius": 3.0}]
	)
	var large := dresser._building_clearing_weight(
		sample_point, "grass", [{"position": Vector2.ZERO, "radius": 6.0}]
	)
	assert(small >= medium)
	assert(medium > large)
	assert(is_equal_approx(
		dresser._building_clearing_weight(
			Vector2(40.0, 0.0),
			"grass",
			[{"position": Vector2.ZERO, "radius": 6.0}]
		),
		1.0
	))

func _test_coast_orientation_matrix() -> void:
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var cases := [
		{"fixture": "res://data/fixtures/coastal_town_initial.json", "direction": Vector2.RIGHT},
		{"fixture": "res://data/fixtures/southern_coast_hamlet.json", "direction": Vector2.DOWN},
	]
	for case: Dictionary in cases:
		var fixture := _load_json(String(case.fixture))
		var world := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
		assert(world.errors.is_empty())
		assert(world.waters.size() == 1)
		var water: Resource = world.waters[0]
		assert(water.seaward_direction.is_equal_approx(case.direction))
		var shore: Vector2 = water.shoreline[water.shoreline.size() / 2]
		var wet_point: Vector2 = shore - water.seaward_direction * 0.6
		var sea_point: Vector2 = shore + water.seaward_direction * 8.0
		assert(world.terrain.sample_shore_wetness(wet_point) > 0.45)
		assert(world.terrain.sample_height(sea_point) < water.sea_level)
	catalog.free()

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
