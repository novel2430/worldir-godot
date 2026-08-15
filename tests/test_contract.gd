extends SceneTree

const ContractValidatorScript = preload("res://scripts/compiler/contract_validator.gd")

func _init() -> void:
    var validator := ContractValidatorScript.new()
    var fixture := _load_json("res://data/fixtures/oweng_semantic_baseline.json")
    _expect_valid("OwenG baseline", validator.validate_compile_result(fixture, {"version": "1", "facts": []}))

    var vocabulary := _catalog_world()
    _expect_valid("active OwenG vocabulary", validator.validate_world_ir(vocabulary))

    var old_region: Dictionary = vocabulary.duplicate(true)
    old_region.regions[0].type = "forest"
    _expect_invalid("old Region vocabulary", validator.validate_world_ir(old_region))

    var old_network: Dictionary = vocabulary.duplicate(true)
    old_network.networks[0].type = "road"
    _expect_invalid("old Network vocabulary", validator.validate_world_ir(old_network))

    var missing_owner: Dictionary = vocabulary.duplicate(true)
    missing_owner.entities[0].placement.relations = []
    _expect_invalid("Entity without owner", validator.validate_world_ir(missing_owner))

    var multi_owner: Dictionary = vocabulary.duplicate(true)
    multi_owner.distributions[0].placement.relations.append({"type": "inside", "target": "r_snow"})
    _expect_invalid("Distribution with multiple owners", validator.validate_world_ir(multi_owner))

    var non_region_owner: Dictionary = vocabulary.duplicate(true)
    non_region_owner.entities[0].placement.relations[0].target = "n_path"
    _expect_invalid("inside target is not Region", validator.validate_world_ir(non_region_owner))

    var nested_region: Dictionary = vocabulary.duplicate(true)
    nested_region.regions[1].placement = {
        "relations": [{"type": "inside", "target": "r_coastal"}]
    }
    _expect_invalid("Region nesting", validator.validate_world_ir(nested_region))

    _test_http_info_versions()
    print("WorldIR OwenG contract validation tests passed")
    quit(0)

func _catalog_world() -> Dictionary:
    var regions := [
        {"id": "r_coastal", "type": "coastal_forest", "placement": {"anchor": "west"}},
        {"id": "r_base", "type": "research_base", "placement": {"anchor": "center"}},
        {"id": "r_snow", "type": "snow_forest", "placement": {"anchor": "east"}},
    ]
    var entities: Array = []
    var entity_types := [
        "rowboat", "tent", "cabin", "research_station", "radar_tower", "warning_sign",
        "cargo_truck", "crate", "maritime_memorial", "ruined_archway", "bunker", "concrete_wall",
    ]
    for index in range(entity_types.size()):
        entities.append({
            "id": "entity_%d" % index,
            "type": entity_types[index],
            "placement": {"relations": [{"type": "inside", "target": "r_base"}]},
        })
    var distributions: Array = []
    for semantic_type in ["tree", "grass", "shrub", "rock"]:
        distributions.append({
            "id": "distribution_%s" % semantic_type,
            "type": semantic_type,
            "placement": {"relations": [{"type": "inside", "target": "r_coastal"}]},
            "population": {"amount": {"mode": "count", "value": 1}},
        })
    return {
        "regions": regions,
        "networks": [{"id": "n_path", "type": "path", "topology": {"from": "west", "to": "east"}}],
        "entities": entities,
        "distributions": distributions,
    }

func _test_http_info_versions() -> void:
    var client := HttpCompilerClient.new()
    var compatible_info := {
        "world_ir_version": "2",
        "world_catalog_version": "1",
        "runtime_context_version": "1",
        "compile_result_version": "1",
    }
    assert(client._is_info_compatible(compatible_info))
    var mismatch: Dictionary = compatible_info.duplicate(true)
    mismatch.world_catalog_version = "2"
    assert(not client._is_info_compatible(mismatch))
    client.free()

func _expect_valid(label: String, errors: PackedStringArray) -> void:
    if not errors.is_empty():
        printerr("FAILED [%s]: %s" % [label, " | ".join(errors)])
        quit(1)

func _expect_invalid(label: String, errors: PackedStringArray) -> void:
    if errors.is_empty():
        printerr("FAILED [%s]: expected validation errors" % label)
        quit(1)

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
