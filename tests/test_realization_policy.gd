extends SceneTree

const RealizationPolicyScript = preload("res://scripts/backend/realization_policy.gd")

func _init() -> void:
    var policy: RefCounted = RealizationPolicyScript.new()
    _test_live_policy(policy)
    _test_candidate_density_semantics(policy)
    _test_spatial_influences()
    _test_world_ir_contract_is_unchanged()
    _test_explicit_distribution_remains_authoritative()
    print("ArtLab realization policy tests passed")
    quit(0)

func _test_live_policy(policy: RefCounted) -> void:
    assert(policy.warnings.is_empty())
    assert(String(policy.get_value("format", "")) == RealizationPolicyScript.FORMAT)
    assert(bool(policy.get_value("source.world_ir_contract_unchanged", false)))
    assert(is_equal_approx(
        policy.number("terrain.geometry.forest_relief_strength", 0.0),
        TerrainResolver.FOREST_RELIEF_STRENGTH
    ))
    assert(policy.text("dressing.density_semantics", "").begins_with("candidate_placement"))
    var meadow: Color = policy.color("surface.palette.meadow_low", Color.BLACK)
    assert(meadow.is_equal_approx(Color(0.19, 0.245, 0.125)))

func _test_candidate_density_semantics(policy: RefCounted) -> void:
    var dresser := ForestDresser.new()
    var area := 7800.0
    var counts := {}
    for decoration_type in ForestDresser.DECORATION_ORDER:
        var rule: Dictionary = policy.dressing_rule(
            decoration_type,
            ForestDresser.RULES[decoration_type]
        )
        var candidate_area := float(rule["target_area_per_candidate_m2"])
        var probability := float(rule["acceptance_probability"])
        var expected := mini(
            int(rule["cap"]),
            int(round(float(int(floor(area / candidate_area))) * probability))
        )
        counts[decoration_type] = dresser.target_count_for_area(area, rule)
        assert(int(counts[decoration_type]) == expected)
    assert(int(counts.grass) > int(counts.bush))
    assert(int(counts.bush) > int(counts.rock))
    assert(int(counts.rock) > int(counts.dead_tree))

func _test_spatial_influences() -> void:
    var dresser := ForestDresser.new()
    var structures := [{"position": Vector2.ZERO, "radius": 2.0}]
    var inner := dresser._building_clearing_weight(
        Vector2.ZERO,
        "grass",
        structures
    )
    var outer := dresser._building_clearing_weight(
        Vector2(100.0, 0.0),
        "grass",
        structures
    )
    assert(is_equal_approx(inner, 0.12))
    assert(is_equal_approx(outer, 1.0))

    var road := ResolvedNetwork.new()
    road.id = "road"
    road.semantic_type = "road"
    road.width = 4.0
    road.curve_points = PackedVector3Array([
        Vector3(-20.0, 0.0, 0.0),
        Vector3(20.0, 0.0, 0.0),
    ])
    var solver := PlacementSolver.new()
    solver.configure(Rect2(-40.0, -40.0, 80.0, 80.0), 99)
    var near_weight := dresser._network_corridor_weight(
        Vector2(0.0, 3.0),
        0.2,
        0.55,
        "grass",
        [road],
        solver
    )
    var far_weight := dresser._network_corridor_weight(
        Vector2(0.0, 20.0),
        0.2,
        0.55,
        "grass",
        [road],
        solver
    )
    assert(near_weight < far_weight)
    assert(is_equal_approx(far_weight, 1.0))

func _test_world_ir_contract_is_unchanged() -> void:
    var validator := ContractValidator.new()
    var valid := _tree_world(1)
    assert(validator.validate_world_ir(valid).is_empty())
    var invalid := valid.duplicate(true)
    invalid["environment"] = {"profile": "snow_forest"}
    assert(not validator.validate_world_ir(invalid).is_empty())

func _test_explicit_distribution_remains_authoritative() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var world_ir := _tree_world(5)
    var before := JSON.stringify(world_ir)
    var world := WorldBackend.new().lower(world_ir, catalog, 1372)
    var sparse_world := WorldBackend.new().lower(_tree_world(2), catalog, 1372)
    assert(world.errors.is_empty())
    assert(sparse_world.errors.is_empty())
    assert(world.find_distribution("trees").instances.size() == 5)
    assert(sparse_world.find_distribution("trees").instances.size() == 2)
    assert(JSON.stringify(world_ir) == before)
    assert(world.terrain.heights == sparse_world.terrain.heights)
    assert(not bool(SceneDiff.new().compare(world, sparse_world).terrain_changed))
    catalog.free()

func _tree_world(count: int) -> Dictionary:
    return {
        "regions": [{"id": "forest", "type": "forest"}],
        "networks": [],
        "entities": [],
        "distributions": [{
            "id": "trees",
            "type": "tree",
            "placement": {
                "relations": [{"type": "inside", "target": "forest"}],
            },
            "population": {
                "amount": {"mode": "count", "value": count},
                "arrangement": {"type": "uniform"},
            },
        }],
    }
