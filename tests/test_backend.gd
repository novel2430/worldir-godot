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
    _test_runtime_binding(catalog)
    _test_anchor_inside_conjunction(catalog)
    _test_large_scale_region_realization(catalog)
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
    assert(resolved.errors.is_empty())
    var town: ResolvedRegion = resolved.find_region("town")
    var road: ResolvedNetwork = resolved.find_network("main_road")
    var houses: ResolvedDistribution = resolved.find_distribution("houses")
    assert(town != null and road != null and houses != null)
    assert(houses.instances.size() == DistributionLowerer.UNSPECIFIED_COUNT)
    for point in road.curve_points:
        assert(Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), town.polygon))
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
    ir["entities"].append({"id": "unknown_landmark", "type": "semantic_type_without_prototype"})
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
