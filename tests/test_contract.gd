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

    print("WorldIR contract validation tests passed")
    quit(0)

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

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
