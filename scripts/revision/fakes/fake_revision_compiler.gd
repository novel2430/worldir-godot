class_name FakeRevisionCompiler
extends CompilerClient

const MODE_SUCCESS := "SUCCESS"
const MODE_ERROR := "ERROR"
const MODE_IR_GAP := "IR_GAP"

var response_mode := MODE_SUCCESS
var result: Dictionary = {}
var defer_response := true
var last_request: Dictionary = {}
var _pending := false

func compile_world(prompt: String, current_ir: Variant, runtime_context: Dictionary) -> void:
	last_request = make_compile_request(prompt, current_ir, runtime_context)
	if not validate_request_or_emit(last_request):
		return
	_pending = true
	if not defer_response:
		deliver()

func deliver() -> void:
	if not _pending:
		return
	_pending = false
	match response_mode:
		MODE_ERROR:
			compiler_error.emit("Injected compile failure")
		MODE_IR_GAP:
			compile_completed.emit({
				"status": "ir_gap",
				"gap": {
					"reason": "Injected unsupported edit",
					"unsupported": ["fake_step_3_gap"],
				},
				"meta": {"request_id": "fake_gap", "mode": "edit"},
			})
		_:
			compile_completed.emit(result.duplicate(true))
