extends SceneTree

const ContractValidatorScript = preload("res://scripts/compiler/contract_validator.gd")

func _init() -> void:
    var fixture_file := FileAccess.open("res://data/fixtures/coastal_town_initial.json", FileAccess.READ)
    assert(fixture_file != null)
    var result: Variant = JSON.parse_string(fixture_file.get_as_text())
    assert(typeof(result) == TYPE_DICTIONARY)

    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var backend := WorldBackend.new()
    var resolved := backend.lower(result.world_ir, catalog, 1337)
    assert(resolved.errors.is_empty())
    assert(resolved.regions.size() == 2)
    assert(resolved.networks.size() == 1)
    assert(resolved.entities.size() == 1)
    assert(resolved.distributions.size() == 2)
    assert(resolved.find_network("main_road").curve_points.size() >= 2)

    _test_density_gradient(result.world_ir, catalog)
    _test_prototype_population_footprints(catalog)
    _test_area_based_density_budget(catalog)
    _test_runtime_binding(catalog)
    _test_forest_has_no_implicit_trees(catalog)
    _test_anchor_inside_conjunction(catalog)
    _test_large_scale_region_realization(catalog)
    _test_network_placement_relations(catalog)
    _test_network_inside_and_houses_along(catalog)
    _test_along_preserves_other_relations(result.world_ir, catalog)
    _test_unsatisfiable_placement_fails(result.world_ir, catalog)
    _test_backend_capability_failure(result.world_ir, catalog)

    print("WorldIR backend smoke tests passed")
    quit(0)

func _test_density_gradient(base_ir: Dictionary, catalog: PrototypeCatalog) -> void:
    var ir: Dictionary = base_ir.duplicate(true)
    var trees: Dictionary = ir["distributions"][1]
    trees["population"] = {
        "amount": {"mode": "count", "value": 60},
        "arrangement": {"type": "random"},
        "density_profile": {
            "type": "gradient",
            "from": {
                "selector": {"type": "near", "target": "main_road"},
                "density": "low",
            },
            "to": {
                "selector": {"type": "anchor", "value": "west"},
                "density": "high",
            },
        },
    }
    var validator = ContractValidatorScript.new()
    assert(validator.validate_world_ir(ir).is_empty())

    var backend_a := WorldBackend.new()
    var backend_b := WorldBackend.new()
    var a := backend_a.lower(ir, catalog, 1337)
    var b := backend_b.lower(ir, catalog, 1337)
    assert(a.errors.is_empty())
    assert(b.errors.is_empty())
    var a_trees: ResolvedDistribution = a.find_distribution("trees")
    var b_trees: ResolvedDistribution = b.find_distribution("trees")
    assert(a_trees != null and b_trees != null)
    assert(a_trees.instances.size() == 60)
    assert(b_trees.instances.size() == 60)
    for i in range(60):
        var ta: Transform3D = a_trees.instances[i]["transform"]
        var tb: Transform3D = b_trees.instances[i]["transform"]
        assert(ta.is_equal_approx(tb))

func _test_area_based_density_budget(catalog: PrototypeCatalog) -> void:
    var small_medium := _lower_density_forest(catalog, "medium", 40.0, 4242)
    var large_low := _lower_density_forest(catalog, "low", 80.0, 4242)
    var large_medium := _lower_density_forest(catalog, "medium", 80.0, 4242)
    var repeated_medium := _lower_density_forest(catalog, "medium", 80.0, 4242)
    var large_high := _lower_density_forest(catalog, "high", 80.0, 4242)
    var medium_houses := _lower_density_distribution(catalog, "house", "medium", 80.0, 4242)

    for resolved in [small_medium, large_low, large_medium, repeated_medium, large_high, medium_houses]:
        assert(resolved.errors.is_empty())

    var small_trees: ResolvedDistribution = small_medium.find_distribution("trees")
    var low_trees: ResolvedDistribution = large_low.find_distribution("trees")
    var medium_trees: ResolvedDistribution = large_medium.find_distribution("trees")
    var repeated_trees: ResolvedDistribution = repeated_medium.find_distribution("trees")
    var high_trees: ResolvedDistribution = large_high.find_distribution("trees")
    var houses: ResolvedDistribution = medium_houses.find_distribution("houses")
    assert(small_trees != null and low_trees != null and medium_trees != null and repeated_trees != null and high_trees != null and houses != null)

    assert(small_trees.instances.size() < medium_trees.instances.size())
    assert(low_trees.instances.size() < medium_trees.instances.size())
    assert(medium_trees.instances.size() < high_trees.instances.size())
    assert(medium_trees.instances.size() == _expected_density_count(catalog, "tree", "medium", 80.0 * 80.0))
    assert(houses.instances.size() == _expected_density_count(catalog, "house", "medium", 80.0 * 80.0))
    assert(medium_trees.instances.size() > int(round(80.0 * 80.0 / 180.0)))
    assert(houses.instances.size() > int(round(80.0 * 80.0 / 550.0)))
    assert(medium_trees.instances.size() == repeated_trees.instances.size())
    for index in range(medium_trees.instances.size()):
        var transform: Transform3D = medium_trees.instances[index]["transform"]
        var repeated_transform: Transform3D = repeated_trees.instances[index]["transform"]
        assert(transform.is_equal_approx(repeated_transform))

func _test_prototype_population_footprints(catalog: PrototypeCatalog) -> void:
    var tree := catalog.get_metadata("tree_01")
    var house := catalog.get_metadata("house_01")
    assert((tree["visual_footprint"] as Vector2).distance_to(Vector2(2.3, 2.3)) < 0.01)
    assert((tree["collision_footprint"] as Vector2).is_equal_approx(Vector2(0.9, 0.9)))
    assert((house["visual_footprint"] as Vector2).is_equal_approx(Vector2(8.0, 10.0)))
    assert((house["collision_footprint"] as Vector2).is_equal_approx(Vector2(7.0, 9.0)))

    # Population occupancy is deliberately smaller than the full visual bounds:
    # crowns/eaves may overlap, while the core footprint still prevents piling up.
    assert(float(tree["population_occupancy_radius"]) < (tree["visual_footprint"] as Vector2).length() * 0.5)
    assert(float(house["population_occupancy_radius"]) < (house["visual_footprint"] as Vector2).length() * 0.5)

func _test_runtime_binding(catalog: PrototypeCatalog) -> void:
    var fixture := _load_json("res://data/fixtures/clearing_to_graveyard.json")
    var payloads := {
        "clearing_01": {
            "aabb2": {"x": -44.0, "z": -15.0, "w": 18.0, "d": 28.0},
            "center": {"x": -35.0, "z": -1.0},
        }
    }
    var backend := WorldBackend.new()
    var resolved := backend.lower(fixture.world_ir, catalog, 1337, fixture.runtime_bindings, payloads)
    assert(resolved.errors.is_empty())
    var graveyard: ResolvedRegion = resolved.find_region("graveyard")
    assert(graveyard != null)
    var rect := _polygon_aabb(graveyard.polygon)
    assert(rect.is_equal_approx(Rect2(-44.0, -15.0, 18.0, 28.0)))

func _test_forest_has_no_implicit_trees(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [{"id": "forest", "type": "forest", "placement": {"anchor": "west"}}],
        "networks": [],
        "entities": [],
        "distributions": [],
    }
    var resolved := WorldBackend.new().lower(ir, catalog, 1337)
    assert(resolved.errors.is_empty())
    assert(resolved.find_region("forest") != null)
    assert(resolved.distributions.is_empty())


func _test_anchor_inside_conjunction(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [
            {"id": "forest", "type": "forest", "placement": {"anchor": "west"}},
            {
                "id": "graveyard",
                "type": "graveyard",
                "placement": {
                    "anchor": "northwest",
                    "relations": [{"type": "inside", "target": "forest"}],
                },
            },
        ],
        "networks": [],
        "entities": [],
        "distributions": [],
    }
    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337)
    assert(resolved.errors.is_empty())
    var forest: ResolvedRegion = resolved.find_region("forest")
    var graveyard: ResolvedRegion = resolved.find_region("graveyard")
    assert(forest != null and graveyard != null)
    var northwest := backend.solver.anchor_rect("northwest")
    for p in graveyard.polygon:
        assert(Geometry2D.is_point_in_polygon(p, forest.polygon))
        assert(northwest.has_point(p) or p.is_equal_approx(northwest.end))


func _test_large_scale_region_realization(catalog: PrototypeCatalog) -> void:
    # Mirrors the Region shape emitted by the real compiler trace:
    # town near coast, forest west of town, coast east of town.
    var ir: Dictionary = {
        "regions": [
            {
                "id": "town",
                "type": "town",
                "placement": {
                    "relations": [{"type": "near", "target": "coast"}],
                },
            },
            {
                "id": "forest",
                "type": "forest",
                "placement": {
                    "relations": [{"type": "direction_of", "target": "town", "direction": "west"}],
                },
            },
            {
                "id": "coast",
                "type": "coast",
                "placement": {
                    "relations": [{"type": "direction_of", "target": "town", "direction": "east"}],
                },
            },
        ],
        "networks": [],
        "entities": [],
        "distributions": [],
    }
    var backend_a: WorldBackend = WorldBackend.new()
    var backend_b: WorldBackend = WorldBackend.new()
    var a: ResolvedWorld = backend_a.lower(ir, catalog, 1337)
    var b: ResolvedWorld = backend_b.lower(ir, catalog, 1337)
    assert(a.errors.is_empty())
    assert(b.errors.is_empty())

    var forest_a: ResolvedRegion = a.find_region("forest")
    var forest_b: ResolvedRegion = b.find_region("forest")
    var coast_a: ResolvedRegion = a.find_region("coast")
    var coast_b: ResolvedRegion = b.find_region("coast")
    assert(forest_a != null and forest_b != null and coast_a != null and coast_b != null)
    assert(forest_a.polygon.size() > 4)
    assert(coast_a.polygon.size() > 4)

    var forest_rect: Rect2 = _polygon_aabb(forest_a.polygon)
    var coast_rect: Rect2 = _polygon_aabb(coast_a.polygon)
    assert(forest_rect.size.x > 45.0)
    assert(forest_rect.size.y > 110.0)
    assert(coast_rect.size.x > 40.0)
    assert(coast_rect.size.y > 110.0)
    assert(is_equal_approx(forest_rect.position.x, a.world_bounds.position.x))
    assert(is_equal_approx(coast_rect.end.x, a.world_bounds.end.x))

    # Same IR + seed must keep the exact procedural Region boundary stable.
    assert(forest_a.polygon.size() == forest_b.polygon.size())
    assert(coast_a.polygon.size() == coast_b.polygon.size())
    for i in range(forest_a.polygon.size()):
        assert(forest_a.polygon[i].is_equal_approx(forest_b.polygon[i]))
    for i in range(coast_a.polygon.size()):
        assert(coast_a.polygon[i].is_equal_approx(coast_b.polygon[i]))

func _test_network_placement_relations(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [
            {"id": "town", "type": "town", "placement": {"anchor": "center"}},
        ],
        "networks": [
            {
                "id": "near_road",
                "type": "road",
                "topology": {"from": "south", "to": "north"},
                "placement": {"relations": [{"type": "near", "target": "town"}]},
            },
            {
                "id": "far_path",
                "type": "path",
                "topology": {"from": "south", "to": "north"},
                "placement": {"relations": [{"type": "far_from", "target": "town"}]},
            },
            {
                "id": "west_path",
                "type": "path",
                "topology": {"from": "south", "to": "north"},
                "placement": {
                    "relations": [{"type": "direction_of", "target": "town", "direction": "west"}],
                },
            },
        ],
        "entities": [],
        "distributions": [],
    }
    var validator := ContractValidatorScript.new()
    assert(validator.validate_world_ir(ir).is_empty())

    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337)
    assert(resolved.errors.is_empty())
    var town: ResolvedRegion = resolved.find_region("town")
    var context := {
        "regions": {"town": town},
        "networks": {},
        "entities": {},
        "distributions": {},
    }
    var near_road: ResolvedNetwork = resolved.find_network("near_road")
    var far_path: ResolvedNetwork = resolved.find_network("far_path")
    var west_path: ResolvedNetwork = resolved.find_network("west_path")
    assert(near_road != null and far_path != null and west_path != null)

    var has_near_point := false
    for point in near_road.curve_points:
        if backend.solver.distance_to_target(Vector2(point.x, point.z), "town", context) <= PlacementSolver.NEAR_THRESHOLD_M:
            has_near_point = true
    assert(has_near_point)

    var has_far_point := false
    for point in far_path.curve_points:
        if backend.solver.distance_to_target(Vector2(point.x, point.z), "town", context) >= PlacementSolver.FAR_THRESHOLD_M:
            has_far_point = true
    assert(has_far_point)

    var town_center := backend.solver.polygon_aabb(town.polygon).get_center()
    var has_west_point := false
    for point in west_path.curve_points:
        if point.x < town_center.x:
            has_west_point = true
    assert(has_west_point)

func _test_network_inside_and_houses_along(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [
            {"id": "town", "type": "town", "placement": {"anchor": "center"}},
        ],
        "networks": [
            {
                "id": "main_road",
                "type": "road",
                "topology": {"from": "south", "to": "north"},
                "placement": {"relations": [{"type": "inside", "target": "town"}]},
            },
        ],
        "entities": [],
        "distributions": [
            {
                "id": "houses",
                "type": "house",
                "placement": {
                    "relations": [
                        {"type": "inside", "target": "town"},
                        {"type": "along", "target": "main_road"},
                    ],
                },
            },
        ],
    }
    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337)
    var repeated := WorldBackend.new().lower(ir, catalog, 1337)
    assert(resolved.errors.is_empty())
    assert(repeated.errors.is_empty())
    var town: ResolvedRegion = resolved.find_region("town")
    var road: ResolvedNetwork = resolved.find_network("main_road")
    var repeated_road: ResolvedNetwork = repeated.find_network("main_road")
    var houses: ResolvedDistribution = resolved.find_distribution("houses")
    assert(town != null and road != null and repeated_road != null and houses != null)
    assert(houses.instances.size() == DistributionLowerer.DEFAULT_POPULATION_BUDGET)
    var expected_start := backend.solver.anchor_point("south")
    var expected_finish := backend.solver.anchor_point("north")
    var actual_start := Vector2(road.curve_points[0].x, road.curve_points[0].z)
    var actual_finish := Vector2(road.curve_points[-1].x, road.curve_points[-1].z)
    assert(actual_start.is_equal_approx(expected_start))
    assert(actual_finish.is_equal_approx(expected_finish))
    assert(road.curve_points.size() == repeated_road.curve_points.size())
    var passes_through_town := false
    for index in range(road.curve_points.size()):
        var point: Vector3 = road.curve_points[index]
        assert(point.is_equal_approx(repeated_road.curve_points[index]))
        if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), town.polygon):
            passes_through_town = true
    assert(passes_through_town)
    for instance in houses.instances:
        var transform: Transform3D = instance["transform"]
        var p := Vector2(transform.origin.x, transform.origin.z)
        assert(Geometry2D.is_point_in_polygon(p, town.polygon))
        assert(p.distance_to(backend.solver.nearest_point_on_network(p, road)) <= PlacementSolver.ALONG_THRESHOLD_M + 0.001)

func _test_along_preserves_other_relations(base_ir: Dictionary, catalog: PrototypeCatalog) -> void:
    var ir: Dictionary = base_ir.duplicate(true)
    var houses: Dictionary = ir["distributions"][0]
    houses["population"] = {"amount": {"mode": "count", "value": 8}}
    houses["placement"] = {
        "relations": [
            {"type": "along", "target": "main_road"},
            {"type": "far_from", "target": "church"},
        ],
    }
    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337)
    assert(resolved.errors.is_empty())
    var church: ResolvedEntity = resolved.find_entity("church")
    var road: ResolvedNetwork = resolved.find_network("main_road")
    var resolved_houses: ResolvedDistribution = resolved.find_distribution("houses")
    assert(church != null and road != null and resolved_houses != null)
    var church_p := Vector2(church.transform.origin.x, church.transform.origin.z)
    for instance in resolved_houses.instances:
        var transform: Transform3D = instance["transform"]
        var p := Vector2(transform.origin.x, transform.origin.z)
        assert(p.distance_to(church_p) >= PlacementSolver.FAR_THRESHOLD_M - 0.001)
        assert(p.distance_to(backend.solver.nearest_point_on_network(p, road)) <= PlacementSolver.ALONG_THRESHOLD_M + 0.001)

func _test_unsatisfiable_placement_fails(base_ir: Dictionary, catalog: PrototypeCatalog) -> void:
    var ir: Dictionary = base_ir.duplicate(true)
    ir["entities"].append({
        "id": "impossible_church",
        "type": "church",
        "placement": {
            "relations": [
                {"type": "near", "target": "main_road"},
                {"type": "far_from", "target": "main_road"},
            ],
        },
    })
    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337)
    assert(not resolved.errors.is_empty())
    var found_placement_error := false
    for error in resolved.errors:
        if String(error).contains("Placement failed for Entity 'impossible_church'"):
            found_placement_error = true
    assert(found_placement_error)


func _test_backend_capability_failure(base_ir: Dictionary, catalog: PrototypeCatalog) -> void:
    var ir: Dictionary = base_ir.duplicate(true)
    ir["entities"].append({"id": "valid_but_unavailable_landmark", "type": "lighthouse"})
    var validator = ContractValidatorScript.new()
    assert(validator.validate_world_ir(ir).is_empty())
    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337)
    assert(not resolved.errors.is_empty())

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed

func _lower_density_forest(catalog: PrototypeCatalog, density: String, size: float, seed_value: int) -> ResolvedWorld:
    return _lower_density_distribution(catalog, "tree", density, size, seed_value)

func _lower_density_distribution(
    catalog: PrototypeCatalog,
    semantic_type: String,
    density: String,
    size: float,
    seed_value: int
) -> ResolvedWorld:
    var distribution_id := "%ss" % semantic_type
    var ir := {
        "regions": [{"id": "forest", "type": "forest"}],
        "networks": [],
        "entities": [],
        "distributions": [{
            "id": distribution_id,
            "type": semantic_type,
            "placement": {"relations": [{"type": "inside", "target": "forest"}]},
            "population": {
                "amount": {"mode": "density", "value": density},
                "arrangement": {"type": "random"},
            },
        }],
    }
    var bindings := [{
        "ir_object_id": "forest",
        "runtime_fact_id": "forest_area",
        "placement": "inside",
    }]
    var payloads := {
        "forest_area": {
            "aabb2": {"x": -size * 0.5, "z": -size * 0.5, "w": size, "d": size},
        },
    }
    return WorldBackend.new().lower(ir, catalog, seed_value, bindings, payloads)

func _expected_density_count(
    catalog: PrototypeCatalog,
    semantic_type: String,
    density: String,
    usable_area: float
) -> int:
    var prototype_id := catalog.choose_prototype(semantic_type)
    var meta := catalog.get_metadata(prototype_id)
    var footprint: Vector2 = meta["population_footprint"]
    var spacing := float(meta["population_spacing"]) * float(DistributionLowerer.DENSITY_SPACING_MULTIPLIERS[density])
    var area_per_instance := (
        (footprint.x + spacing)
        * (footprint.y + spacing)
        * DistributionLowerer.RANDOM_PACKING_LOSS
    )
    var cap := int(DistributionLowerer.POPULATION_CAPS.get(semantic_type, DistributionLowerer.DEFAULT_POPULATION_CAP))
    return clampi(int(round(usable_area / area_per_instance)), 1, cap)

func _polygon_aabb(poly: PackedVector2Array) -> Rect2:
    var min_x := poly[0].x
    var max_x := poly[0].x
    var min_y := poly[0].y
    var max_y := poly[0].y
    for p in poly:
        min_x = minf(min_x, p.x)
        max_x = maxf(max_x, p.x)
        min_y = minf(min_y, p.y)
        max_y = maxf(max_y, p.y)
    return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
