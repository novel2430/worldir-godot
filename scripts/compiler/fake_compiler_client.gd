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
    elif "墓地" in prompt or "graveyard" in lowered:
        fixture = "clearing_to_graveyard.json"
    elif "恢复" in prompt or "restore" in lowered:
        fixture = "restore_forest.json"
    elif current_ir == null:
        fixture = "coastal_town_initial.json"
    else:
        var echo_result := {
            "status": "ok",
            "world_ir": current_ir.duplicate(true),
            "runtime_bindings": [],
            "runtime_fact_ops": [],
            "meta": {"request_id": "fake_echo", "mode": "edit", "route": "bypass"},
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
