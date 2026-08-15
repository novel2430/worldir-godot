extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)

    _test_project_config_is_live(catalog)
    _test_override_drives_lowering(catalog)

    print("Backend configuration tests passed")
    quit(0)

func _test_project_config_is_live(catalog: PrototypeCatalog) -> void:
    var file_values: Variant = JSON.parse_string(
        FileAccess.get_file_as_string("res://data/configs/backend.json")
    )
    assert(typeof(file_values) == TYPE_DICTIONARY)
    assert(not (file_values as Dictionary).has("density_counts"))

    var backend := WorldBackend.new()
    var world := backend.lower(_empty_world(), catalog)
    assert(world.errors.is_empty())
    assert(world.seed == int(file_values["seed"]))
    assert(world.world_bounds.size.is_equal_approx(
        Vector2.ONE * float(file_values["world_size_m"])
    ))
    assert(is_equal_approx(backend.solver.near_threshold_m, float(file_values["near_threshold_m"])))
    assert(is_equal_approx(backend.solver.far_threshold_m, float(file_values["far_threshold_m"])))
    assert(is_equal_approx(backend.solver.along_threshold_m, float(file_values["along_threshold_m"])))
    assert(is_equal_approx(
        backend.region_claim_resolver.default_budget_m2,
        float(file_values["default_region_claim_budget_m2"])
    ))
    assert(is_equal_approx(
        float(backend.region_claim_resolver.budgets_m2["forest"]),
        float(file_values["region_claim_budgets_m2"]["forest"])
    ))
    assert(backend.distribution_lowerer.default_population_budget == int(file_values["default_population_budget"]))
    assert(is_equal_approx(
        backend.distribution_lowerer.random_packing_loss,
        float(file_values["random_packing_loss"])
    ))

func _test_override_drives_lowering(catalog: PrototypeCatalog) -> void:
    var overrides := {
        "world_size_m": 96.0,
        "seed": 2468,
        "near_threshold_m": 7.0,
        "far_threshold_m": 13.0,
        "along_threshold_m": 5.0,
        "default_region_claim_budget_m2": 1200.0,
        "region_claim_budgets_m2": {"forest": 1800.0},
        "default_population_budget": 3,
        "random_packing_loss": 1.35,
        "density_spacing_multipliers": {"low": 2.4, "medium": 1.2, "high": 0.6},
        "population_caps": {"tree": 4},
    }
    var backend := WorldBackend.new(overrides)
    var unspecified_world := backend.lower(_tree_world({}), catalog)
    assert(unspecified_world.errors.is_empty())
    assert(unspecified_world.seed == 2468)
    assert(unspecified_world.world_bounds.is_equal_approx(Rect2(-48.0, -48.0, 96.0, 96.0)))
    assert(unspecified_world.find_distribution("trees").instances.size() == 3)
    assert(is_equal_approx(backend.solver.near_threshold_m, 7.0))
    assert(is_equal_approx(backend.solver.far_threshold_m, 13.0))
    assert(is_equal_approx(backend.solver.along_threshold_m, 5.0))
    assert(is_equal_approx(backend.region_claim_resolver.default_budget_m2, 1200.0))
    assert(is_equal_approx(float(backend.region_claim_resolver.budgets_m2["forest"]), 1800.0))

    var density_world := WorldBackend.new(overrides).lower(
        _tree_world({"amount": {"mode": "density", "value": "high"}}),
        catalog
    )
    assert(density_world.errors.is_empty())
    assert(density_world.find_distribution("trees").instances.size() == 4)

    var target := ResolvedEntity.new()
    target.id = "target"
    target.transform = Transform3D.IDENTITY
    var context := {
        "regions": {},
        "networks": {},
        "entities": {"target": target},
        "distributions": {},
    }
    assert(backend.solver.is_semantically_valid(
        Vector2(6.9, 0.0),
        {"relations": [{"type": "near", "target": "target"}]},
        context
    ))
    assert(not backend.solver.is_semantically_valid(
        Vector2(7.1, 0.0),
        {"relations": [{"type": "near", "target": "target"}]},
        context
    ))
    assert(not backend.solver.is_semantically_valid(
        Vector2(12.9, 0.0),
        {"relations": [{"type": "far_from", "target": "target"}]},
        context
    ))
    assert(backend.solver.is_semantically_valid(
        Vector2(13.1, 0.0),
        {"relations": [{"type": "far_from", "target": "target"}]},
        context
    ))

func _tree_world(population: Dictionary) -> Dictionary:
    return {
        "regions": [{"id": "forest", "type": "forest"}],
        "networks": [],
        "entities": [],
        "distributions": [{
            "id": "trees",
            "type": "tree",
            "placement": {"relations": [{"type": "inside", "target": "forest"}]},
            "population": population,
        }],
    }

func _empty_world() -> Dictionary:
    return {"regions": [], "networks": [], "entities": [], "distributions": []}
