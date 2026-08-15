extends SceneTree

const CoordinatorScript = preload("res://scripts/revision/current_chunk_revision_coordinator.gd")
const FakeRevisionCompilerScript = preload("res://scripts/revision/fakes/fake_revision_compiler.gd")
const WorldStateScript = preload("res://scripts/app/world_state.gd")

const C5 := Vector2i(5, 5)
const C6 := Vector2i(6, 5)
const C7 := Vector2i(7, 5)

var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var state_store := WorldStateScript.new()
	root.add_child(state_store)
	state_store.commit(_world_ir(10, 2), [])

	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var runtime := SceneRuntime.new()
	runtime.prototype_catalog = catalog
	runtime.scene_transition.duration_scale = 0.02
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	manager.keep_dormant_mounted = true
	root.add_child(manager)
	manager.configure(catalog, runtime, world_root)
	_expect(
		manager.initialize_world(state_store.current_ir, 0, 7301, _world_position(C5)),
		"Real A must initialize the IR0 3x3 world"
	)
	# Keep preview work deferred and deterministic under explicit test control.
	manager.set_process(false)
	manager.set_physics_process(false)

	var target_root := manager.get_chunk_root(C5)
	var target_scene := target_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
	var target_scene_id := target_scene.get_instance_id()
	var compiler := FakeRevisionCompilerScript.new()
	compiler.result = _compile_result()
	root.add_child(compiler)
	var coordinator := CoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.configure(state_store, compiler, manager, runtime, 7301)
	var outcomes: Array[Dictionary] = []
	coordinator.transaction_finished.connect(func(success: bool, message: String) -> void:
		outcomes.append({"success": success, "message": message})
	)

	_expect(coordinator.submit_prompt("树少一点，房屋多一点"), "Real A transaction must start")
	_expect(manager.is_chunk_pinned(C5), "Real A must pin captured C5")
	_expect(manager.update_player_world_position(_world_position(C6)), "Player may move to C6 during compile")
	_expect(manager.get_current_chunk_coord() == C6, "A must make C6 the later Current")
	compiler.deliver()
	_expect(coordinator.state == "APPLY", "Real A Candidate must reach APPLY")
	_expect(state_store.current_ir_revision == 0, "Global revision must remain IR0 during APPLY")
	var outcome := await _wait_for_outcome(outcomes)

	_expect(outcome.get("success", false), "Real A IR0 -> IR1 transaction must succeed")
	_expect(coordinator.last_transaction.transaction_chunk_coord == C5, "Prompt target must remain captured C5")
	_expect(state_store.current_ir_revision == 1, "Current transition success must commit IR1")
	_expect(not manager.is_chunk_pinned(C5), "Real A target must unpin after commit")
	var c5_record := manager.get_record(C5)
	_expect(c5_record.source_ir_revision == 1, "C5 installed source must be IR1")
	_expect(c5_record.target_ir_revision == 1, "C5 installed target must be IR1")
	_expect(c5_record.resolved_chunk.revision == 1, "C5 ResolvedChunk provenance must be IR1")
	_expect(
		(manager.get_chunk_root(C5).get_node(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D).get_instance_id()
			== target_scene_id,
		"Real A Current rewrite must patch C5 content in place"
	)
	var c6_record := manager.get_record(C6)
	_expect(c6_record.authority == ChunkRecord.AuthorityState.COMMITTED, "Later Current C6 must be COMMITTED")
	_expect(c6_record.source_ir_revision == 0 and c6_record.target_ir_revision == 0, "C6 is Historical for this captured Prompt and must preserve IR0")

	var stale_preview_count := 0
	for record: ChunkRecord in manager.get_active_records():
		if record.authority != ChunkRecord.AuthorityState.PROVISIONAL:
			continue
		_expect(record.target_ir_revision == 1, "Every active PROVISIONAL must target IR1")
		if record.source_ir_revision == 0 and record.target_ir_revision == 1:
			stale_preview_count += 1
	_expect(stale_preview_count > 0, "Real A Preview may remain stale after global commit")

	var future_coord := Vector2i(12, 12)
	_expect(manager.get_record(future_coord) == null, "Future space must not have a pre-created record")
	var future := manager.ensure_chunk(future_coord)
	_expect(future != null and future.source_ir_revision == 1, "Future first materialization must use latest committed IR1")

	# Move through stale C7: A must ensure latest before promotion. C6 then
	# becomes Historical IR0 and must reload its own snapshot under global IR1.
	_expect(manager.update_player_world_position(_world_position(C7)), "A entry barrier must bring C7 latest before promotion")
	_expect(manager.get_record(C7).source_ir_revision == 1, "C7 must be IR1 before becoming Current")
	var c6_signature := c6_record.resolved_chunk.deterministic_signature()
	_expect(manager.unload_chunk(C6), "Historical C6 must be unloadable")
	var c6_reloaded := manager.ensure_chunk(C6)
	_expect(c6_reloaded.source_ir_revision == 0, "Historical reload must preserve source IR0")
	_expect(c6_reloaded.target_ir_revision == 0, "Historical reload must preserve target IR0")
	_expect(c6_reloaded.resolved_chunk.deterministic_signature() == c6_signature, "Historical reload must restore the committed IR0 snapshot")

	if failures == 0:
		print("Current Chunk Revision real A integration tests passed")
	quit(1 if failures > 0 else 0)

func _wait_for_outcome(outcomes: Array[Dictionary]) -> Dictionary:
	for _frame in range(900):
		if not outcomes.is_empty():
			return outcomes[0]
		await process_frame
	_expect(false, "Timed out waiting for real A transaction")
	return {}

func _world_position(coord: Vector2i) -> Vector3:
	var origin := ChunkMath.chunk_origin(coord)
	return Vector3(origin.x + 80.0, 4.0, origin.y + 80.0)

func _compile_result() -> Dictionary:
	return {
		"status": "ok",
		"world_ir": _world_ir(5, 6),
		"runtime_bindings": [],
		"runtime_fact_ops": [],
		"meta": {"request_id": "real_a_step_4", "mode": "edit", "route": "deliberate"},
	}

func _world_ir(tree_count: int, house_count: int) -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [{
			"id": "main_road",
			"type": "road",
			"topology": {"from": "south", "to": "north"},
		}],
		"entities": [],
		"distributions": [
			{
				"id": "trees",
				"type": "tree",
				"placement": {"relations": [{"type": "inside", "target": "forest"}]},
				"population": {
					"amount": {"mode": "count", "value": tree_count},
					"arrangement": {"type": "uniform"},
				},
			},
			{
				"id": "houses",
				"type": "house",
				"placement": {"relations": [{"type": "inside", "target": "forest"}]},
				"population": {
					"amount": {"mode": "count", "value": house_count},
					"arrangement": {"type": "uniform"},
				},
			},
		],
	}

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
