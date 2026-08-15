class_name WorldCoordinator
extends Node

signal status_changed(message: String)
signal busy_changed(busy: bool)
signal world_committed(resolved: ResolvedWorld)

@export var use_http_compiler: bool = false
@export var compiler_base_url: String = "http://127.0.0.1:8787"
@export var compiler_timeout_seconds: float = 1200.0
# A negative value delegates the seed to data/configs/backend.json.
@export var world_seed: int = -1
@export var auto_generate_demo: bool = true

@onready var world_root: Node3D = %WorldRoot
@onready var world_state: WorldState = %WorldState
@onready var prototype_catalog: PrototypeCatalog = %PrototypeCatalog
@onready var scene_runtime: SceneRuntime = %SceneRuntime
@onready var runtime_fact_manager: RuntimeFactManager = %RuntimeFactManager
@onready var chunk_manager: ChunkManager = %ChunkManager
@onready var player: Node3D = %Player

var compiler: CompilerClient
var current_resolved: ResolvedWorld = null
var busy := false
var revision_coordinator: CurrentChunkRevisionCoordinator = null
var _revision_in_flight := false

func _ready() -> void:
	runtime_fact_manager.fact_created.connect(_on_fact_created)
	if use_http_compiler:
		var http_compiler := HttpCompilerClient.new()
		http_compiler.base_url = compiler_base_url
		http_compiler.timeout_seconds = compiler_timeout_seconds
		compiler = http_compiler
	else:
		compiler = FakeCompilerClient.new()
	compiler.name = "CompilerClient"
	add_child(compiler)
	compiler.compile_completed.connect(_on_compile_completed)
	compiler.compiler_error.connect(_on_compiler_error)
	compiler.readiness_changed.connect(_on_readiness_changed)
	chunk_manager.configure(prototype_catalog, scene_runtime, world_root, player)
	if player.has_method("set_chunk_manager"):
		player.call("set_chunk_manager", chunk_manager)
	revision_coordinator = CurrentChunkRevisionCoordinator.new()
	revision_coordinator.name = "CurrentChunkRevisionCoordinator"
	add_child(revision_coordinator)
	revision_coordinator.configure(
		world_state,
		compiler,
		chunk_manager,
		scene_runtime,
		_effective_world_seed()
	)
	revision_coordinator.state_changed.connect(_on_revision_state_changed)
	revision_coordinator.transaction_finished.connect(_on_revision_transaction_finished)
	compiler.start()

func submit_prompt(prompt: String) -> void:
	if busy or prompt.strip_edges().is_empty(): return
	busy = true
	busy_changed.emit(true)
	if world_state.current_ir == null:
		status_changed.emit("Compiling initial semantic world...")
		compiler.compile_world(prompt, null, world_state.runtime_context())
		return
	_revision_in_flight = true
	var started := revision_coordinator.submit_prompt(prompt)
	if not started:
		_revision_in_flight = false
		_finish(false, revision_coordinator.last_error if not revision_coordinator.last_error.is_empty() else "Revision transaction could not start")

func create_demo_clearing() -> void:
	runtime_fact_manager.create_demo_clearing()

func _on_readiness_changed(ready: bool, detail: String) -> void:
	status_changed.emit(detail)
	if ready and auto_generate_demo and world_state.current_ir == null:
		submit_prompt("生成一个废弃海边小镇：西边森林，东边海岸，主路南北贯穿，北边教堂靠近道路，房屋沿路，森林里有树。")

func _on_compile_completed(result: Dictionary) -> void:
	if _revision_in_flight:
		# CurrentChunkRevisionCoordinator owns every edit response after boot.
		return
	if String(result.get("status", "")) == "ir_gap":
		_finish(false, "IR GAP: %s" % String(result.get("gap", {}).get("reason", "unsupported semantics")))
		return
	if String(result.get("status", "")) != "ok" or typeof(result.get("world_ir")) != TYPE_DICTIONARY:
		_finish(false, "Invalid compiler result")
		return

	var candidate_ir: Dictionary = result.world_ir
	var candidate_facts := world_state.candidate_facts_after_ops(result.get("runtime_fact_ops", []))
	if not chunk_manager.initialize_world(
		candidate_ir,
		0,
		_effective_world_seed(),
		player.global_position
	):
		_finish(false, "Chunk system rejected initial Candidate World")
		return
	world_state.commit(candidate_ir, candidate_facts)
	var current_record := chunk_manager.get_record(chunk_manager.get_current_chunk_coord())
	current_resolved = current_record.resolved_chunk
	world_committed.emit(current_resolved)
	_finish(true, "V1 world committed: 3x3 Chunk window at revision 0")

func _on_compiler_error(message: String) -> void:
	if _revision_in_flight:
		return
	_finish(false, "Compiler error: %s" % message)

func _on_revision_state_changed(next_state: String) -> void:
	if not _revision_in_flight and next_state == CurrentChunkRevisionCoordinator.STATE_STABLE:
		return
	status_changed.emit("Revision: %s" % next_state)

func _on_revision_transaction_finished(success: bool, message: String) -> void:
	if not _revision_in_flight:
		return
	_revision_in_flight = false
	if success and revision_coordinator.last_transaction != null:
		var coord: Vector2i = revision_coordinator.last_transaction.transaction_chunk_coord
		var record := chunk_manager.get_record(coord)
		if record != null:
			current_resolved = record.resolved_chunk
			world_committed.emit(current_resolved)
	_finish(success, message)

func _on_fact_created(fact: Dictionary, payload: Dictionary) -> void:
	world_state.add_runtime_fact(fact, payload)
	status_changed.emit("Runtime Fact created: %s (spatial payload stays local)" % String(fact.get("id", "")))

func _finish(_success: bool, message: String) -> void:
	busy = false; busy_changed.emit(false); status_changed.emit(message)

func _effective_world_seed() -> int:
	return world_seed if world_seed >= 0 else 1337
