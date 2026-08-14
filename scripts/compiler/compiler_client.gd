class_name CompilerClient
extends Node

const ContractValidatorScript = preload("res://scripts/compiler/contract_validator.gd")

signal compile_completed(result: Dictionary)
signal compiler_error(message: String)
signal readiness_changed(ready: bool, detail: String)

var contract_validator = ContractValidatorScript.new()

func start() -> void:
    readiness_changed.emit(true, "compiler ready")

func compile_world(_prompt: String, _current_ir: Variant, _runtime_context: Dictionary) -> void:
    compiler_error.emit("CompilerClient.compile_world() is abstract")

func make_compile_request(prompt: String, current_ir: Variant, runtime_context: Dictionary) -> Dictionary:
    return {
        "prompt": prompt,
        "current_ir": current_ir,
        "runtime_context": runtime_context,
    }

func validate_request_or_emit(request: Dictionary) -> bool:
    var errors = contract_validator.validate_compile_request(request)
    if errors.is_empty():
        return true
    compiler_error.emit("CompileRequest violates V1 contract: %s" % " | ".join(errors))
    return false

func validate_result_or_emit(result: Dictionary, request_runtime_context: Dictionary) -> bool:
    var errors = contract_validator.validate_compile_result(result, request_runtime_context)
    if errors.is_empty():
        return true
    compiler_error.emit("CompileResult violates V1 contract: %s" % " | ".join(errors))
    return false
