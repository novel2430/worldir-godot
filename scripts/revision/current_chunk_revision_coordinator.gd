class_name CurrentChunkRevisionCoordinator
extends Node

const ContractValidatorScript = preload("res://scripts/compiler/contract_validator.gd")
const RevisionTransactionScript = preload("res://scripts/revision/revision_transaction.gd")
const ChunkRevisionIntegrationScript = preload("res://scripts/revision/chunk_revision_integration.gd")

const STATE_STABLE := "STABLE"
const STATE_CAPTURE := "CAPTURE"
const STATE_COMPILE := "COMPILE"
const STATE_PREPARE := "PREPARE"
const STATE_APPLY := "APPLY"
const STATE_COMMIT := "COMMIT"

signal state_changed(state: String)
signal transaction_finished(success: bool, message: String)
signal preview_routing_finished(report: Dictionary)

var world_state: WorldState
var compiler: CompilerClient
var chunk_manager: Variant
var scene_runtime: SceneRuntime
var world_seed := 1
var transition_mode := SceneRuntime.TRANSITION_MODE_FULL_REWRITE

var state := STATE_STABLE
var state_history: Array[String] = [STATE_STABLE]
var active_transaction: Variant = null
var last_transaction: Variant = null
var last_patch: Dictionary = {}
var last_error := ""
var last_preview_report: Dictionary = {}
var revision_integration := ChunkRevisionIntegrationScript.new()

var _request_runtime_context: Dictionary = {}
var _prepared_transition: Dictionary = {}
var _candidate_chunk: Variant = null
var _candidate_facts: Array = []
var _contract_validator := ContractValidatorScript.new()

func configure(
	state_store: WorldState,
	compiler_client: CompilerClient,
	manager: Variant,
	runtime: SceneRuntime,
	seed: int = 1
) -> void:
	if compiler != null:
		var completed_callable := Callable(self, "_on_compile_completed")
		var error_callable := Callable(self, "_on_compiler_error")
		if compiler.compile_completed.is_connected(completed_callable):
			compiler.compile_completed.disconnect(completed_callable)
		if compiler.compiler_error.is_connected(error_callable):
			compiler.compiler_error.disconnect(error_callable)
	world_state = state_store
	compiler = compiler_client
	chunk_manager = manager
	scene_runtime = runtime
	world_seed = seed
	revision_integration.configure(manager)
	compiler.compile_completed.connect(_on_compile_completed)
	compiler.compiler_error.connect(_on_compiler_error)

func submit_prompt(prompt: String) -> bool:
	if state != STATE_STABLE or prompt.strip_edges().is_empty():
		return false
	if world_state == null or compiler == null or chunk_manager == null or scene_runtime == null:
		return false
	var integration_errors := revision_integration.contract_errors()
	if not integration_errors.is_empty():
		last_error = "A contract unavailable: %s" % " | ".join(integration_errors)
		return false

	_set_state(STATE_CAPTURE)
	var transaction := RevisionTransactionScript.new()
	transaction.capture(
		world_state.current_ir_revision,
		chunk_manager.get_current_chunk_coord()
	)
	active_transaction = transaction
	last_transaction = transaction
	last_patch = {}
	last_error = ""
	last_preview_report = {}
	chunk_manager.pin_chunk(transaction.transaction_chunk_coord)
	_request_runtime_context = world_state.runtime_context()
	_set_state(STATE_COMPILE)
	compiler.compile_world(prompt, world_state.current_ir, _request_runtime_context)
	return true

func _on_compile_completed(result: Dictionary) -> void:
	if state != STATE_COMPILE or active_transaction == null:
		return
	_process_compile_result(result)

func _on_compiler_error(message: String) -> void:
	if active_transaction == null:
		return
	_abort("Compile failure: %s" % message)

func _process_compile_result(result: Dictionary) -> void:
	_set_state(STATE_PREPARE)
	var validation_errors := _contract_validator.validate_compile_result(
		result,
		_request_runtime_context
	)
	if not validation_errors.is_empty():
		_abort("Candidate result validation failed: %s" % " | ".join(validation_errors))
		return
	if String(result.get("status", "")) == "ir_gap":
		_abort("IR GAP: %s" % String(result.get("gap", {}).get("reason", "unsupported")))
		return

	var target_coord: Vector2i = active_transaction.transaction_chunk_coord
	var official_record: Dictionary = chunk_manager.get_record(target_coord)
	var old_chunk: Variant = official_record.get("resolved_chunk")
	var chunk_root: Node3D = chunk_manager.get_chunk_root(target_coord)
	if old_chunk == null or not (old_chunk is ResolvedWorld) or chunk_root == null:
		_abort("Transaction target is not materialized")
		return
	if chunk_root.get_node_or_null(SceneRuntime.CHUNK_CONTENT_NAME) == null:
		_abort("Transaction target Scene is not mounted")
		return
	if not scene_runtime.is_transition_mode_supported(transition_mode):
		_abort("Unsupported transition mode")
		return

	_candidate_facts = world_state.candidate_facts_after_ops(result.get("runtime_fact_ops", []))
	active_transaction.prepare(
		result["world_ir"],
		chunk_manager.get_active_records()
	)
	var generation_overrides := _generation_overrides(result.get("runtime_bindings", []))
	var constraints: Dictionary = chunk_manager.get_boundary_constraints(target_coord)
	_candidate_chunk = chunk_manager.generate_chunk(
		target_coord,
		active_transaction.candidate_ir,
		active_transaction.candidate_revision,
		world_seed,
		constraints,
		generation_overrides
	)
	if _candidate_chunk == null or not (_candidate_chunk is ResolvedWorld):
		_abort("GenerateChunk failed")
		return
	if (
		_candidate_chunk.get("coord") != target_coord
		or int(_candidate_chunk.get("revision")) != active_transaction.candidate_revision
	):
		_abort("GenerateChunk returned mismatched provenance")
		return

	_prepared_transition = scene_runtime.prepare_chunk_transition(old_chunk, _candidate_chunk)
	if _prepared_transition.is_empty():
		_abort("Candidate scene build failed")
		return
	if world_state.current_ir_revision != active_transaction.base_revision:
		_abort("Official revision changed during PREPARE")
		return

	_set_state(STATE_APPLY)
	var patch_value: Variant = await scene_runtime.apply_prepared_chunk_transition(
		chunk_root,
		_candidate_chunk,
		_prepared_transition,
		transition_mode
	)
	assert(typeof(patch_value) == TYPE_DICTIONARY)
	last_patch = patch_value

	_set_state(STATE_COMMIT)
	var committed: bool = active_transaction.commit_to(world_state, _candidate_facts)
	assert(committed)
	chunk_manager.install_revision(
		target_coord,
		_candidate_chunk,
		active_transaction.candidate_revision
	)
	# Preview routing is deliberately post-commit and is not part of the strong
	# Current transaction failure domain. A only receives latest target/rebuild
	# requests; its scheduler decides when those Chunks are actually rebuilt.
	last_preview_report = revision_integration.publish_committed_revision(
		active_transaction.candidate_revision,
		target_coord
	)
	preview_routing_finished.emit(last_preview_report)
	_finish_success("Revision %d committed to %s" % [
		active_transaction.candidate_revision,
		target_coord,
	])

## A's player-promotion lifecycle may await this hook. It does not move the
## player or mutate authority; it only enforces source == target before entry.
func ensure_chunk_latest_for_entry(coord: Vector2i) -> bool:
	return await revision_integration.ensure_latest_before_entry(coord)

func _generation_overrides(runtime_bindings: Array) -> Dictionary:
	var payloads := {}
	for value in runtime_bindings:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var fact_id := String((value as Dictionary).get("runtime_fact_id", ""))
		if world_state.spatial_payloads.has(fact_id):
			payloads[fact_id] = world_state.spatial_payloads[fact_id].duplicate(true)
	return {
		"runtime_bindings": runtime_bindings.duplicate(true),
		"spatial_payloads": payloads,
	}

func _abort(message: String) -> void:
	last_error = message
	if not _prepared_transition.is_empty():
		scene_runtime.discard_prepared_chunk_transition(_prepared_transition)
	if active_transaction != null:
		active_transaction.abort()
		chunk_manager.unpin_chunk(active_transaction.transaction_chunk_coord)
	_clear_candidate_state()
	active_transaction = null
	_set_state(STATE_STABLE)
	transaction_finished.emit(false, message)

func _finish_success(message: String) -> void:
	chunk_manager.unpin_chunk(active_transaction.transaction_chunk_coord)
	_clear_candidate_state()
	active_transaction = null
	_set_state(STATE_STABLE)
	transaction_finished.emit(true, message)

func _clear_candidate_state() -> void:
	_prepared_transition = {}
	_candidate_chunk = null
	_candidate_facts = []
	_request_runtime_context = {}

func _set_state(next_state: String) -> void:
	state = next_state
	state_history.append(next_state)
	state_changed.emit(next_state)
