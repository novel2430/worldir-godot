extends SceneTree

const RealizationPolicyScript = preload("res://scripts/backend/realization_policy.gd")

func _init() -> void:
    var policy: RefCounted = RealizationPolicyScript.new()
    _test_live_policy(policy)
    _test_policy_loading_and_fallbacks(policy)
    _test_candidate_density_semantics(policy)
    _test_spatial_influences()
    _test_world_ir_contract_is_unchanged()
    _test_explicit_distribution_remains_authoritative()
    print("ArtLab realization policy tests passed")
    quit(0)

func _test_live_policy(policy: RefCounted) -> void:
    assert(policy.warnings.is_empty())
    assert(policy.loaded_from_disk)
    assert(String(policy.get_value("format", "")) == RealizationPolicyScript.FORMAT)
    assert(policy.fingerprint().length() == 64)
    var diagnostics: Dictionary = policy.diagnostic_snapshot()
    assert(int(diagnostics.format_version) == RealizationPolicyScript.FORMAT_VERSION)
    assert(String(diagnostics.fingerprint) == policy.fingerprint())
    assert(not diagnostics.has("values"))
    assert(bool(policy.get_value("source.world_ir_contract_unchanged", false)))
    assert(is_equal_approx(
        policy.number("terrain.geometry.forest_relief_strength", 0.0),
        TerrainResolver.FOREST_RELIEF_STRENGTH
    ))
    assert(policy.text("dressing.density_semantics", "").begins_with("candidate_placement"))
    var meadow: Color = policy.color("surface.palette.meadow_low", Color.BLACK)
    assert(meadow.is_equal_approx(Color(0.19, 0.245, 0.125)))

func _test_policy_loading_and_fallbacks(default_policy: RefCounted) -> void:
    var fixture_dir := "user://artlab_policy_fixtures"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_dir))

    var missing_path := "%s/missing.json" % fixture_dir
    var missing: RefCounted = RealizationPolicyScript.new(missing_path)
    assert(not missing.loaded_from_disk)
    assert(not missing.warnings.is_empty())
    assert(missing.fingerprint() == RealizationPolicyScript.new("").fingerprint())

    var malformed_path := "%s/malformed.json" % fixture_dir
    _write_policy_fixture(malformed_path, "{not-json")
    var malformed: RefCounted = RealizationPolicyScript.new(malformed_path)
    assert(not malformed.loaded_from_disk)
    assert(not malformed.warnings.is_empty())
    assert(malformed.fingerprint() == RealizationPolicyScript.new("").fingerprint())

    var unsupported_path := "%s/unsupported.json" % fixture_dir
    _write_policy_fixture(unsupported_path, JSON.stringify({"format": "worldir-godot-artlab-realization-policy-v2"}))
    var unsupported: RefCounted = RealizationPolicyScript.new(unsupported_path)
    assert(not unsupported.loaded_from_disk)
    assert("unsupported format" in String(unsupported.warnings[0]))
    assert(unsupported.fingerprint() == RealizationPolicyScript.new("").fingerprint())

    var wrong_type_path := "%s/wrong_type.json" % fixture_dir
    _write_policy_fixture(wrong_type_path, JSON.stringify({
        "format": RealizationPolicyScript.FORMAT,
        "terrain": {"geometry": {"base_height_limit_m": "invalid"}},
    }))
    var wrong_type: RefCounted = RealizationPolicyScript.new(wrong_type_path)
    assert(wrong_type.loaded_from_disk)
    assert(not wrong_type.warnings.is_empty())
    assert(is_equal_approx(
        wrong_type.number("terrain.geometry.base_height_limit_m", -1.0),
        RealizationPolicyScript.DEFAULT_VALUES.terrain.geometry.base_height_limit_m
    ))

    var partial_path := "%s/partial.json" % fixture_dir
    _write_policy_fixture(partial_path, JSON.stringify({
        "format": RealizationPolicyScript.FORMAT,
        "terrain": {"geometry": {"base_height_limit_m": 4.25}},
    }))
    var partial: RefCounted = RealizationPolicyScript.new(partial_path)
    assert(partial.loaded_from_disk)
    assert(partial.warnings.is_empty())
    assert(is_equal_approx(partial.number("terrain.geometry.base_height_limit_m", 0.0), 4.25))
    assert(is_equal_approx(
        partial.number("terrain.geometry.forest_relief_strength", 0.0),
        default_policy.number("terrain.geometry.forest_relief_strength", -1.0)
    ))
    assert(partial.fingerprint() != default_policy.fingerprint())

    for file_name in ["malformed.json", "unsupported.json", "wrong_type.json", "partial.json"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [fixture_dir, file_name]))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_dir))

func _write_policy_fixture(path: String, contents: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    assert(file != null)
    file.store_string(contents)
    file.close()

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
