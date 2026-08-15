extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var file_values: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/configs/backend.json"))
    assert(typeof(file_values) == TYPE_DICTIONARY)
    for region_type in ["coastal_forest", "research_base", "snow_forest"]:
        assert(file_values.region_claim_budgets_m2.has(region_type))

    var overrides := {
        "world_size_m": 96.0,
        "seed": 2468,
        "default_population_budget": 3,
        "population_caps": {"tree": 4},
        "region_claim_budgets_m2": {"coastal_forest": 1800.0},
    }
    var ir := {
        "regions": [{"id": "coastal", "type": "coastal_forest"}],
        "networks": [], "entities": [],
        "distributions": [{
            "id": "trees", "type": "tree",
            "placement": {"relations": [{"type": "inside", "target": "coastal"}]},
            "population": {},
        }],
    }
    var backend := WorldBackend.new(overrides)
    var world := backend.lower(ir, catalog)
    assert(world.errors.is_empty())
    assert(world.seed == 2468)
    assert(world.world_bounds.is_equal_approx(Rect2(-48.0, -48.0, 96.0, 96.0)))
    assert(world.find_distribution("trees").instances.size() == 3)
    assert(is_equal_approx(float(backend.region_claim_resolver.budgets_m2.coastal_forest), 1800.0))
    print("Backend configuration tests passed")
    quit(0)
