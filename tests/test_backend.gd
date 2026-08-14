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
