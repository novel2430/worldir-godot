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

var compiler: CompilerClient
var backend := WorldBackend.new()
var current_resolved: ResolvedWorld = null
var busy := false

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
	compiler.start()

func submit_prompt(prompt: String) -> void:
	if busy or prompt.strip_edges().is_empty(): return
	busy = true; busy_changed.emit(true)
	status_changed.emit("Compiling semantic world...")
	compiler.compile_world(prompt, world_state.current_ir, world_state.runtime_context())

func create_demo_clearing() -> void:
	runtime_fact_manager.create_demo_clearing()

func _on_readiness_changed(ready: bool, detail: String) -> void:
	status_changed.emit(detail)
	if ready and auto_generate_demo and world_state.current_ir == null:
		submit_prompt("生成一个连续世界：西侧海岸森林，中部研究基地，东侧雪林，并用一条路径连接。")

func _on_compile_completed(result: Dictionary) -> void:
	if String(result.get("status", "")) == "ir_gap":
		_finish(false, "IR GAP: %s" % String(result.get("gap", {}).get("reason", "unsupported semantics")))
		return
	if String(result.get("status", "")) != "ok" or typeof(result.get("world_ir")) != TYPE_DICTIONARY:
		_finish(false, "Invalid compiler result")
		return

	var candidate_ir: Dictionary = result.world_ir
	var candidate_facts := world_state.candidate_facts_after_ops(result.get("runtime_fact_ops", []))
	var candidate_resolved := backend.lower(
		candidate_ir,
		prototype_catalog,
		world_seed,
		result.get("runtime_bindings", []),
		world_state.spatial_payloads
	)
	if not candidate_resolved.errors.is_empty():
		_finish(false, "Backend rejected Candidate World: %s" % " | ".join(candidate_resolved.errors))
		return

	var candidate_scene := scene_runtime.build_candidate(candidate_resolved, prototype_catalog)
	if candidate_scene == null:
		_finish(false, "Scene candidate failed; old world preserved")
		return

	if current_resolved == null:
		scene_runtime.commit_candidate(world_root, candidate_scene)
	else:
		await scene_runtime.transition_candidate(
			world_root,
			candidate_scene,
			current_resolved,
			candidate_resolved
		)
	world_state.commit(candidate_ir, candidate_facts)
	current_resolved = candidate_resolved
	world_committed.emit(candidate_resolved)
	var warning_text := "" if candidate_resolved.warnings.is_empty() else " | warnings: %s" % ", ".join(candidate_resolved.warnings)
	_finish(true, "World committed: %d regions, %d networks, %d entities%s" % [candidate_resolved.regions.size(), candidate_resolved.networks.size(), candidate_resolved.entities.size(), warning_text])

func _on_compiler_error(message: String) -> void:
	_finish(false, "Compiler error: %s" % message)

func _on_fact_created(fact: Dictionary, payload: Dictionary) -> void:
	world_state.add_runtime_fact(fact, payload)
	status_changed.emit("Runtime Fact created: %s (spatial payload stays local)" % String(fact.get("id", "")))

func _finish(_success: bool, message: String) -> void:
	busy = false; busy_changed.emit(false); status_changed.emit(message)
