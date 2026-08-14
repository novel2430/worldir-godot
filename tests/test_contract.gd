extends SceneTree

const ContractValidatorScript = preload("res://scripts/compiler/contract_validator.gd")

func _init() -> void:
    var validator = ContractValidatorScript.new()

    var initial := _load_json("res://data/fixtures/coastal_town_initial.json")
    var empty_context := {"version": "1", "facts": []}
    _expect_valid("initial fixture", validator.validate_compile_result(initial, empty_context))

    var clearing_fact := {
        "id": "clearing_01",
        "kind": "marked_area",
        "mark": "cleared",
        "location": {"inside": "forest", "anchor": "east"},
        "affected_type": "tree",
        "count": 23,
    }
    var edit_context := {"version": "1", "facts": [clearing_fact]}
    var graveyard := _load_json("res://data/fixtures/clearing_to_graveyard.json")
    _expect_valid("graveyard fixture", validator.validate_compile_result(graveyard, edit_context))

    var restore := _load_json("res://data/fixtures/restore_forest.json")
    _expect_valid("restore fixture", validator.validate_compile_result(restore, edit_context))

    var gap := _load_json("res://data/fixtures/ir_gap.json")
    _expect_valid("ir_gap fixture", validator.validate_compile_result(gap, edit_context))

    var bad_route: Dictionary = graveyard.duplicate(true)
    bad_route["meta"]["route"] = "fake"
    _expect_invalid("bad route", validator.validate_compile_result(bad_route, edit_context))

    var bad_density: Dictionary = initial["world_ir"].duplicate(true)
    var trees: Dictionary = bad_density["distributions"][1]
    trees["population"]["density_profile"] = {
        "type": "gradient",
        "from": {
            "selector": {"type": "near", "target": "main_road"},
            "density": "low",
        },
        "to": {
            "selector": {"type": "anchor", "value": "west"},
            "density": "high",
        },
    }
    _expect_invalid("density + density_profile", validator.validate_world_ir(bad_density))

    var bad_unknown: Dictionary = initial["world_ir"].duplicate(true)
    bad_unknown["entities"][0]["mesh_path"] = "forbidden_backend_field"
    _expect_invalid("unknown backend field", validator.validate_world_ir(bad_unknown))

    var bad_initial_request := {
        "prompt": "hello",
        "current_ir": null,
        "runtime_context": edit_context,
    }
    _expect_invalid("initial request with runtime facts", validator.validate_compile_request(bad_initial_request))

    # JSON.parse_string() decodes JSON numbers as float in Godot. Integral floats
    # must still satisfy the Contract's integer semantics.
    var fractional_count: Dictionary = initial["world_ir"].duplicate(true)
    fractional_count["distributions"][0]["population"]["amount"]["value"] = 12.5
    _expect_invalid("fractional count", validator.validate_world_ir(fractional_count))

    _test_catalog_v1_types(validator)
    _test_id_and_anchor_contract(validator)
    _test_http_info_versions()

    print("WorldIR contract validation tests passed")
    quit(0)

func _test_catalog_v1_types(validator: ContractValidator) -> void:
    var catalog_world := {
        "regions": [
            {"id": "r_town", "type": "town"},
            {"id": "r_village", "type": "village"},
            {"id": "r_forest", "type": "forest"},
            {"id": "r_coast", "type": "coast"},
            {"id": "r_graveyard", "type": "graveyard"},
            {"id": "r_district", "type": "district"},
            {"id": "r_field", "type": "field"},
            {"id": "r_swamp", "type": "swamp"},
        ],
        "networks": [
            {"id": "n_road", "type": "road", "topology": {"from": "south", "to": "north"}},
            {"id": "n_path", "type": "path", "topology": {"from": "west", "to": "east"}},
        ],
        "entities": [
            {"id": "e_church", "type": "church"},
            {"id": "e_lighthouse", "type": "lighthouse"},
            {"id": "e_tower", "type": "tower"},
            {"id": "e_bridge", "type": "bridge"},
            {"id": "e_radio", "type": "radio_tower"},
            {"id": "e_gas", "type": "gas_station"},
        ],
        "distributions": [
            {"id": "d_house", "type": "house"},
            {"id": "d_tree", "type": "tree"},
            {"id": "d_tombstone", "type": "tombstone"},
            {"id": "d_lamp", "type": "lamp"},
        ],
    }
    _expect_valid("all World Catalog V1 types", validator.validate_world_ir(catalog_world))

    var unknown_type: Dictionary = catalog_world.duplicate(true)
    unknown_type["entities"][0]["type"] = "castle"
    _expect_invalid("non-Catalog type", validator.validate_world_ir(unknown_type))

func _test_id_and_anchor_contract(validator: ContractValidator) -> void:
    var blank_id := _empty_world()
    blank_id["regions"].append({"id": "   ", "type": "forest"})
    _expect_invalid("blank World IR id", validator.validate_world_ir(blank_id))

    var whole_placement := _empty_world()
    whole_placement["regions"].append({
        "id": "forest",
        "type": "forest",
        "placement": {"anchor": "whole"},
    })
    _expect_valid("placement anchor whole", validator.validate_world_ir(whole_placement))

    var whole_selector := _empty_world()
    whole_selector["regions"].append({"id": "forest", "type": "forest"})
    whole_selector["distributions"].append({
        "id": "trees",
        "type": "tree",
        "population": {
            "density_profile": {
                "type": "gradient",
                "from": {"selector": {"type": "anchor", "value": "whole"}, "density": "low"},
                "to": {"selector": {"type": "anchor", "value": "west"}, "density": "high"},
            },
        },
    })
    _expect_invalid("density selector anchor whole", validator.validate_world_ir(whole_selector))

func _test_http_info_versions() -> void:
    var client := HttpCompilerClient.new()
    var compatible_info := {
        "world_ir_version": "2",
        "world_catalog_version": "1",
        "runtime_context_version": "1",
        "compile_result_version": "1",
    }
    _expect_true("matching /info versions", client._is_info_compatible(compatible_info))
    var catalog_mismatch: Dictionary = compatible_info.duplicate(true)
    catalog_mismatch["world_catalog_version"] = "2"
    _expect_true("world catalog mismatch rejected", not client._is_info_compatible(catalog_mismatch))
    var readiness: Dictionary = {}
    client.readiness_changed.connect(func(ready: bool, detail: String) -> void:
        readiness["ready"] = ready
        readiness["detail"] = detail
    )
    client._phase = "info"
    client._on_request_completed(
        HTTPRequest.RESULT_SUCCESS,
        200,
        PackedStringArray(),
        JSON.stringify(catalog_mismatch).to_utf8_buffer()
    )
    _expect_true("catalog mismatch emits not-ready", readiness.get("ready") == false)
    _expect_true("catalog mismatch emits protocol mismatch", readiness.get("detail") == "Protocol version mismatch")
    _expect_true("catalog mismatch returns client to idle", client._phase == "idle")
    client.free()

func _expect_valid(label: String, errors: PackedStringArray) -> void:
    if errors.is_empty():
        return
    printerr("FAILED [%s]: %s" % [label, " | ".join(errors)])
    quit(1)

func _expect_invalid(label: String, errors: PackedStringArray) -> void:
    if not errors.is_empty():
        return
    printerr("FAILED [%s]: expected validation errors, got none" % label)
    quit(1)

func _expect_true(label: String, condition: bool) -> void:
    if condition:
        return
    printerr("FAILED [%s]" % label)
    quit(1)

func _empty_world() -> Dictionary:
    return {"regions": [], "networks": [], "entities": [], "distributions": []}

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
