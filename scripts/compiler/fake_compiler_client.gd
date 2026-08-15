class_name FakeCompilerClient
extends CompilerClient

const FIXTURE_DIR := "res://data/fixtures/"

func start() -> void:
    readiness_changed.emit(true, "Fake compiler ready (contract-validated JSON fixtures)")

func compile_world(prompt: String, current_ir: Variant, runtime_context: Dictionary) -> void:
    var request := make_compile_request(prompt, current_ir, runtime_context)
    if not validate_request_or_emit(request):
        return

    var lowered := prompt.to_lower()
    var fixture := ""
    if "50" in prompt or "50m" in lowered:
        fixture = "ir_gap.json"
    elif current_ir == null:
        fixture = "oweng_final_world.json"
    else:
        var edited_ir: Dictionary = current_ir.duplicate(true)
        var edit_kind := "noop"
        if (
            ("snow" in lowered and "rock" in lowered and ("less" in lowered or "fewer" in lowered))
            or ("雪" in prompt and "石头" in prompt and ("少" in prompt or "减少" in prompt))
        ):
            if _set_distribution_density(edited_ir, "snow_rocks", "medium"):
                edit_kind = "snow_rocks_high_to_medium"
        elif (
            ("coastal" in lowered and "tree" in lowered and "more" in lowered)
            or ("海岸" in prompt and "树" in prompt and ("多" in prompt or "增加" in prompt))
        ):
            if _set_distribution_density(edited_ir, "coastal_trees", "high"):
                edit_kind = "coastal_trees_medium_to_high"
        var echo_result := {
            "status": "ok",
            "world_ir": edited_ir,
            "runtime_bindings": [],
            "runtime_fact_ops": [],
            "meta": {"request_id": "fake_%s" % edit_kind, "mode": "edit", "route": "bypass"},
        }
        if validate_result_or_emit(echo_result, runtime_context):
            compile_completed.emit(echo_result)
        return

    var data := _load_fixture(fixture)
    if data.is_empty():
        compiler_error.emit("Failed to load fake compiler fixture: %s" % fixture)
        return
    if validate_result_or_emit(data, runtime_context):
        compile_completed.emit(data)

func _load_fixture(file_name: String) -> Dictionary:
    var file := FileAccess.open(FIXTURE_DIR + file_name, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _set_distribution_density(world_ir: Dictionary, object_id: String, density: String) -> bool:
    for item: Dictionary in world_ir.get("distributions", []):
        if String(item.get("id", "")) != object_id:
            continue
        var population: Dictionary = item.get("population", {})
        var amount: Dictionary = population.get("amount", {})
        amount["mode"] = "density"
        amount["value"] = density
        population["amount"] = amount
        item["population"] = population
        return true
    return false
