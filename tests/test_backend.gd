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
    assert(resolved.find_entity("church").prototype_id == "church_01")

    _test_density_gradient(result.world_ir, catalog)
    _test_prototype_population_footprints(catalog)
    _test_kaykit_baseline_prototypes(catalog)
    _test_seeded_visual_realization(resolved)
    _test_afternoon_environment()
    _test_area_based_density_budget(catalog)
    _test_runtime_instantiates_catalog_assets(resolved, catalog)
    _test_runtime_binding(catalog)
    _test_forest_has_no_implicit_trees(catalog)
    _test_single_unconstrained_region_fallback(catalog)
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
    var repeated_houses := _lower_density_distribution(catalog, "house", "medium", 80.0, 4242)

    for resolved in [small_medium, large_low, large_medium, repeated_medium, large_high, medium_houses, repeated_houses]:
        assert(resolved.errors.is_empty())

    var small_trees: ResolvedDistribution = small_medium.find_distribution("trees")
    var low_trees: ResolvedDistribution = large_low.find_distribution("trees")
    var medium_trees: ResolvedDistribution = large_medium.find_distribution("trees")
    var repeated_trees: ResolvedDistribution = repeated_medium.find_distribution("trees")
    var high_trees: ResolvedDistribution = large_high.find_distribution("trees")
    var houses: ResolvedDistribution = medium_houses.find_distribution("houses")
    var repeated_house_instances: ResolvedDistribution = repeated_houses.find_distribution("houses")
    assert(small_trees != null and low_trees != null and medium_trees != null and repeated_trees != null and high_trees != null and houses != null and repeated_house_instances != null)

    assert(small_trees.instances.size() < medium_trees.instances.size())
    assert(low_trees.instances.size() < medium_trees.instances.size())
    # A safety cap may make adjacent density levels equal for very small models.
    assert(medium_trees.instances.size() <= high_trees.instances.size())
    assert(medium_trees.instances.size() == _expected_density_count(catalog, "tree", "medium", 80.0 * 80.0))
    assert(houses.instances.size() == _expected_density_count(catalog, "house", "medium", 80.0 * 80.0))
    assert(medium_trees.instances.size() > int(round(80.0 * 80.0 / 180.0)))
    assert(houses.instances.size() > int(round(80.0 * 80.0 / 550.0)))
    assert(medium_trees.instances.size() == repeated_trees.instances.size())
    var used_tree_prototypes := {}
    for index in range(medium_trees.instances.size()):
        var transform: Transform3D = medium_trees.instances[index]["transform"]
        var repeated_transform: Transform3D = repeated_trees.instances[index]["transform"]
        assert(transform.is_equal_approx(repeated_transform))
        var prototype_id := String(medium_trees.instances[index]["prototype_id"])
        used_tree_prototypes[prototype_id] = true
        assert(prototype_id == String(repeated_trees.instances[index]["prototype_id"]))
    assert(used_tree_prototypes.size() > 1)
    var used_house_prototypes := {}
    assert(houses.instances.size() == repeated_house_instances.instances.size())
    for index in range(houses.instances.size()):
        var instance: Dictionary = houses.instances[index]
        var repeated_instance: Dictionary = repeated_house_instances.instances[index]
        var prototype_id := String(instance["prototype_id"])
        used_house_prototypes[prototype_id] = true
        assert(prototype_id == String(repeated_instance["prototype_id"]))
        assert((instance["transform"] as Transform3D).is_equal_approx(repeated_instance["transform"] as Transform3D))
    assert(used_house_prototypes.size() == 2)

func _test_prototype_population_footprints(catalog: PrototypeCatalog) -> void:
    var tree := catalog.get_metadata("tree_01")
    var house := catalog.get_metadata("house_01")
    assert((tree["visual_footprint"] as Vector2).distance_to(Vector2(4.294, 4.389)) < 0.02)
    assert((tree["collision_footprint"] as Vector2).distance_to(Vector2(1.026, 1.026)) < 0.002)
    assert((house["visual_footprint"] as Vector2).distance_to(Vector2(7.92, 8.537)) < 0.02)
    assert((house["collision_footprint"] as Vector2).is_equal_approx(Vector2(7.5, 8.0)))

    # Population occupancy is deliberately smaller than the full visual bounds:
    # crowns/eaves may overlap, while the core footprint still prevents piling up.
    assert(float(tree["population_occupancy_radius"]) < (tree["visual_footprint"] as Vector2).length() * 0.5)
    assert(float(house["population_occupancy_radius"]) < (house["visual_footprint"] as Vector2).length() * 0.5)

func _test_seeded_visual_realization(resolved: ResolvedWorld) -> void:
    var houses: ResolvedDistribution = resolved.find_distribution("houses")
    var trees: ResolvedDistribution = resolved.find_distribution("trees")
    var forest: ResolvedRegion = resolved.find_region("forest")
    assert(houses != null and trees != null and forest != null)

    var minimum_house_scale := INF
    var maximum_house_scale := 0.0
    for instance in houses.instances:
        var scale := (instance["transform"] as Transform3D).basis.get_scale().x
        minimum_house_scale = minf(minimum_house_scale, scale)
        maximum_house_scale = maxf(maximum_house_scale, scale)
        assert(scale >= 0.92 - 0.001 and scale <= 1.08 + 0.001)
    assert(maximum_house_scale - minimum_house_scale > 0.05)

    var minimum_tree_scale := INF
    var maximum_tree_scale := 0.0
    var shallow_edge_count := 0
    var total_edge_distance := 0.0
    for instance in trees.instances:
        var transform: Transform3D = instance["transform"]
        var scale := transform.basis.get_scale().x
        minimum_tree_scale = minf(minimum_tree_scale, scale)
        maximum_tree_scale = maxf(maximum_tree_scale, scale)
        var point := Vector2(transform.origin.x, transform.origin.z)
        var edge_distance := _distance_to_polygon_edge(point, forest.polygon)
        total_edge_distance += edge_distance
        if edge_distance < 4.0:
            shallow_edge_count += 1
    assert(minimum_tree_scale >= 0.90 - 0.001)
    assert(maximum_tree_scale <= 1.15 * 1.28 + 0.001)
    assert(maximum_tree_scale > 1.15) # Seeded occasional canopy landmark.
    assert(float(shallow_edge_count) / float(trees.instances.size()) < 0.20)
    assert(total_edge_distance / float(trees.instances.size()) > 8.0)

func _test_afternoon_environment() -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    assert(packed != null)
    var scene := packed.instantiate() as Node3D
    assert(scene != null)
    var world_environment := scene.get_node("WorldEnvironment") as WorldEnvironment
    var sun := scene.get_node("Sun") as DirectionalLight3D
    assert(world_environment.environment.background_mode == Environment.BG_SKY)
    assert(world_environment.environment.sky != null)
    assert(world_environment.environment.fog_enabled)
    assert(world_environment.environment.ambient_light_energy > 0.65)
    assert(sun.light_color.r > sun.light_color.b)
    assert(sun.rotation_degrees.x > -50.0 and sun.rotation_degrees.x < -25.0)
    scene.free()

func _test_kaykit_baseline_prototypes(catalog: PrototypeCatalog) -> void:
    var tree_ids := [
        "tree_01",
        "tree_02",
        "tree_03",
        "tree_04",
        "tree_05",
        "tree_06",
    ]
    assert(catalog.get_prototype_ids("tree") == tree_ids)
    assert(catalog.get_prototype_ids("house") == ["house_01", "house_02"])
    assert(catalog.get_prototype_ids("church") == ["church_01"])
    assert(catalog.choose_prototype("tree") == tree_ids[0])
    for prototype_id in tree_ids:
        var scene := catalog.get_scene(prototype_id)
        assert(scene != null)
        var instance := scene.instantiate() as WorldPrototype
        assert(instance != null)
        assert(instance.prototype_id == prototype_id)
        assert(instance.semantic_type == "tree")
        var collision_shapes := instance.find_children("*", "CollisionShape3D", true, false)
        assert(collision_shapes.size() == 1)
        assert((collision_shapes[0] as CollisionShape3D).shape is CapsuleShape3D)
        var metadata := catalog.get_metadata(prototype_id)
        var visual_footprint: Vector2 = metadata.get("visual_footprint", Vector2.ZERO)
        var collision_footprint: Vector2 = metadata.get("collision_footprint", Vector2.ZERO)
        assert(visual_footprint.x > 0.0 and visual_footprint.y > 0.0)
        assert(collision_footprint.x > 0.0 and collision_footprint.y > 0.0)
        assert(collision_footprint.x < visual_footprint.x)
        instance.free()

    for prototype_id in ["house_01", "house_02", "church_01"]:
        var scene := catalog.get_scene(prototype_id)
        assert(scene != null)
        var instance := scene.instantiate() as WorldPrototype
        assert(instance != null)
        assert(instance.prototype_id == prototype_id)
        assert(instance.semantic_type == ("church" if prototype_id == "church_01" else "house"))
        assert(instance.find_children("*", "MeshInstance3D", true, false).size() > 0)
        assert(instance.find_children("*", "CollisionShape3D", true, false).size() == 1)
        instance.free()

func _test_runtime_instantiates_catalog_assets(resolved: ResolvedWorld, catalog: PrototypeCatalog) -> void:
    var runtime := SceneRuntime.new()
    var candidate := runtime.build_candidate(resolved, catalog)
    assert(candidate != null)
    var church := candidate.get_node_or_null("Entities/church") as WorldPrototype
    assert(church != null)
    assert(church.prototype_id == "church_01")
    assert(church.find_children("*", "MeshInstance3D", true, false).size() > 0)
    var distribution_nodes := candidate.get_node("Distributions").find_children("*", "WorldPrototype", true, false)
    assert(not distribution_nodes.is_empty())
    # Resolved Regions remain inspectable semantic nodes, but their old stacked
    # color polygons are replaced by one terrain surface carrying blended masks.
    assert(candidate.get_node("Regions/forest").get_child_count() == 0)
    var terrain_body := candidate.get_node("Terrain/WorldSurface") as StaticBody3D
    var terrain_mesh := terrain_body.get_node("TerrainMesh") as MeshInstance3D
    var terrain_collision := terrain_body.get_node("TerrainCollision") as CollisionShape3D
    assert(terrain_mesh.material_override is ShaderMaterial)
    assert(terrain_collision.shape is ConcavePolygonShape3D)
    var terrain_arrays: Array = terrain_mesh.mesh.surface_get_arrays(0)
    var terrain_colors: PackedColorArray = terrain_arrays[Mesh.ARRAY_COLOR]
    assert(terrain_colors.size() == resolved.terrain.grid_size * resolved.terrain.grid_size)
    var has_forest_influence := false
    var has_local_dirt_influence := false
    for color in terrain_colors:
        has_forest_influence = has_forest_influence or color.r > 0.5
        has_local_dirt_influence = has_local_dirt_influence or color.a > 0.5
    assert(has_forest_influence and has_local_dirt_influence)
    candidate.free()
    runtime.free()

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


func _test_single_unconstrained_region_fallback(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [{"id": "forest", "type": "forest"}],
        "networks": [],
        "entities": [],
        "distributions": [{
            "id": "trees",
            "type": "tree",
            "placement": {"relations": [{"type": "inside", "target": "forest"}]},
            "population": {"amount": {"mode": "density", "value": "medium"}},
        }],
    }
    var source_before := JSON.stringify(ir)
    assert(ContractValidatorScript.new().validate_world_ir(ir).is_empty())
    var first := WorldBackend.new().lower(ir, catalog, 7013)
    var second := WorldBackend.new().lower(ir, catalog, 7013)
    assert(first.errors.is_empty() and second.errors.is_empty())
    assert(JSON.stringify(ir) == source_before)

    var forest: ResolvedRegion = first.find_region("forest")
    var repeated_forest: ResolvedRegion = second.find_region("forest")
    assert(forest != null and repeated_forest != null)
    assert(forest.polygon.size() == 4)
    assert(_polygon_aabb(forest.polygon).is_equal_approx(first.world_bounds))
    assert(forest.polygon == repeated_forest.polygon)

    var trees: ResolvedDistribution = first.find_distribution("trees")
    var repeated_trees: ResolvedDistribution = second.find_distribution("trees")
    assert(trees != null and repeated_trees != null)
    assert(not trees.instances.is_empty())
    assert(trees.instances.size() == _expected_density_count(
        catalog,
        "tree",
        "medium",
        first.world_bounds.get_area()
    ))
    assert(trees.instances.size() == repeated_trees.instances.size())
    for index in range(trees.instances.size()):
        var item: Dictionary = trees.instances[index]
        var repeated_item: Dictionary = repeated_trees.instances[index]
        var transform: Transform3D = item["transform"]
        assert(Geometry2D.is_point_in_polygon(
            Vector2(transform.origin.x, transform.origin.z),
            forest.polygon
        ))
        assert(item["prototype_id"] == repeated_item["prototype_id"])
        assert(transform.is_equal_approx(repeated_item["transform"] as Transform3D))

    assert(first.terrain != null)
    assert(first.terrain.world_bounds.is_equal_approx(first.world_bounds))
    assert(first.terrain.sample_surface_mask(first.world_bounds.get_center()).r > 0.9)
    assert(not first.decorations.is_empty())
    for decoration: ResolvedDecoration in first.decorations:
        assert(decoration.region_id == forest.id)
        for item in decoration.instances:
            var origin: Vector3 = (item["transform"] as Transform3D).origin
            assert(Geometry2D.is_point_in_polygon(Vector2(origin.x, origin.z), forest.polygon))

    # The fallback is deliberately not generalized to every unplaced Region.
    var multi_region_ir := {
        "regions": [
            {"id": "unconstrained_forest", "type": "forest"},
            {"id": "field", "type": "field", "placement": {"anchor": "east"}},
        ],
        "networks": [],
        "entities": [],
        "distributions": [],
    }
    var multi := WorldBackend.new().lower(multi_region_ir, catalog, 7013)
    assert(multi.errors.is_empty())
    var multi_forest: ResolvedRegion = multi.find_region("unconstrained_forest")
    assert(multi_forest != null)
    assert(not _polygon_aabb(multi_forest.polygon).is_equal_approx(multi.world_bounds))


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
        var nearest := backend.solver.nearest_point_on_network(p, road)
        var direction_to_road := Vector3(nearest.x - p.x, 0.0, nearest.y - p.y).normalized()
        assert(Geometry2D.is_point_in_polygon(p, town.polygon))
        assert(p.distance_to(nearest) <= PlacementSolver.ALONG_THRESHOLD_M + 0.001)
        assert(p.distance_to(nearest) >= road.width * 0.5 + 5.0)
        assert(transform.basis.z.normalized().dot(direction_to_road) >= cos(deg_to_rad(12.1)))

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
    var footprint := Vector2.ZERO
    var preferred_spacing := 0.0
    for prototype_id in catalog.get_prototype_ids(semantic_type):
        var meta := catalog.get_metadata(prototype_id)
        var candidate_footprint: Vector2 = meta["population_footprint"]
        footprint.x = maxf(footprint.x, candidate_footprint.x)
        footprint.y = maxf(footprint.y, candidate_footprint.y)
        preferred_spacing = maxf(preferred_spacing, float(meta["population_spacing"]))
    var spacing := preferred_spacing * float(DistributionLowerer.DENSITY_SPACING_MULTIPLIERS[density])
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

func _distance_to_polygon_edge(point: Vector2, polygon: PackedVector2Array) -> float:
    var result := INF
    for index in range(polygon.size()):
        var closest := Geometry2D.get_closest_point_to_segment(
            point,
            polygon[index],
            polygon[(index + 1) % polygon.size()]
        )
        result = minf(result, point.distance_to(closest))
    return result
