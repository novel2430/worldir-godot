class_name HttpCompilerClient
extends CompilerClient

@export var base_url: String = "http://127.0.0.1:8787"
@export var timeout_seconds: float = 120.0

var _http: HTTPRequest
var _phase: String = "idle"
var _pending_runtime_context: Dictionary = {"version": "1", "facts": []}

func _ready() -> void:
    _ensure_http()

func start() -> void:
    _ensure_http()
    if _phase != "idle":
        readiness_changed.emit(false, "Compiler request already in progress")
        return
    _phase = "health"
    var err := _http.request(base_url + "/health")
    if err != OK:
        _phase = "idle"
        readiness_changed.emit(false, "Failed to start /health request: %s" % error_string(err))

func compile_world(prompt: String, current_ir: Variant, runtime_context: Dictionary) -> void:
    _ensure_http()
    if _phase != "idle":
        compiler_error.emit("Compiler request already in progress")
        return

    var payload := make_compile_request(prompt, current_ir, runtime_context)
    if not validate_request_or_emit(payload):
        return

    _pending_runtime_context = runtime_context.duplicate(true)
    _phase = "compile"
    var err := _http.request(
        base_url + "/v1/compile",
        PackedStringArray(["Content-Type: application/json"]),
        HTTPClient.METHOD_POST,
        JSON.stringify(payload)
    )
    if err != OK:
        _phase = "idle"
        compiler_error.emit("Failed to start compile request: %s" % error_string(err))

func _ensure_http() -> void:
    if _http != null:
        return
    _http = HTTPRequest.new()
    _http.timeout = timeout_seconds
    add_child(_http)
    _http.request_completed.connect(_on_request_completed)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var phase := _phase
    _phase = "idle"
    if result != HTTPRequest.RESULT_SUCCESS:
        _emit_failure(phase, "Transport failure (%s)" % result)
        return

    var body_text := body.get_string_from_utf8()
    var data: Variant = JSON.parse_string(body_text)
    if response_code != 200:
        _emit_failure(phase, "HTTP %s: %s" % [response_code, body_text.left(500)])
        return
    if typeof(data) != TYPE_DICTIONARY:
        _emit_failure(phase, "HTTP 200 but response body is not a JSON object")
        return

    var response: Dictionary = data
    if phase == "health":
        if String(response.get("status", "")) != "ok":
            readiness_changed.emit(false, "Server health check failed")
            return
        _phase = "info"
        var err := _http.request(base_url + "/info")
        if err != OK:
            _phase = "idle"
            readiness_changed.emit(false, "Failed to start /info request: %s" % error_string(err))
    elif phase == "info":
        var compatible := (
            String(response.get("world_ir_version", "")) == "2"
            and String(response.get("runtime_context_version", "")) == "1"
            and String(response.get("compile_result_version", "")) == "1"
        )
        readiness_changed.emit(compatible, "Server protocol compatible" if compatible else "Protocol version mismatch")
    elif phase == "compile":
        if validate_result_or_emit(response, _pending_runtime_context):
            compile_completed.emit(response)

func _emit_failure(phase: String, message: String) -> void:
    if phase in ["health", "info"]:
        readiness_changed.emit(false, message)
    else:
        compiler_error.emit(message)
