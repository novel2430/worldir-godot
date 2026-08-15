extends SceneTree

const FakeRevisionCompilerScript = preload("res://scripts/revision/fakes/fake_revision_compiler.gd")

const C5 := Vector2i(5, 5)
const C6 := Vector2i(6, 5)
const C7 := Vector2i(7, 5)
const C8 := Vector2i(8, 5)

var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var state := WorldState.new()
	root.add_child(state)
	state.commit(_world_ir(10, 2), [])
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var runtime := SceneRuntime.new()
	runtime.scene_transition.duration_scale = 0.01
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	manager.keep_dormant_mounted = true
	root.add_child(manager)
	manager.configure(catalog, runtime, world_root)
	_expect(manager.initialize_world(state.current_ir, 0, 7301, _position(C5)), "IR0 3x3 must initialize at C5")
	manager.set_process(false)

	_expect(manager.update_player_world_position(_position(C6)), "Player must move C5 -> C6")
	var c5 := manager.get_record(C5)
	_expect(c5.authority == ChunkRecord.AuthorityState.COMMITTED, "C5 must become Historical COMMITTED")
	_expect(c5.source_ir_revision == 0, "Historical C5 must remain IR0")
	var c6_old := manager.get_record(C6).resolved_chunk

	var compiler := FakeRevisionCompilerScript.new()
	compiler.result = {
		"status": "ok",
		"world_ir": _world_ir(5, 6),
		"runtime_bindings": [],
		"runtime_fact_ops": [],
		"meta": {"request_id": "step5_e2e", "mode": "edit", "route": "deliberate"},
	}
	root.add_child(compiler)
	var coordinator := CurrentChunkRevisionCoordinator.new()
	root.add_child(coordinator)
	coordinator.configure(state, compiler, manager, runtime, 7301)
	var outcomes: Array[Dictionary] = []
	coordinator.transaction_finished.connect(func(success: bool, message: String):
		outcomes.append({"success": success, "message": message})
	)
	_expect(coordinator.submit_prompt("树少一点，沿路增加一些房子。"), "Prompt transaction must start at C6")
	compiler.deliver()
	var outcome := await _wait_for_outcome(outcomes)
	_expect(bool(outcome.get("success", false)), "IR0 -> IR1 Current transaction must succeed")
	_expect(state.current_ir_revision == 1, "Global design revision must commit IR1")
	var c6 := manager.get_record(C6)
	_expect(c6.source_ir_revision == 1 and c6.target_ir_revision == 1, "Current C6 must install IR1")
	_expect(
		runtime.last_transition_mode_by_coord[C6] == SceneRuntime.TRANSITION_MODE_FULL_REWRITE,
		"Current C6 must use FULL_REWRITE"
	)
	_expect(runtime.scene_transition.last_patch_summary.mode == "FULL_REWRITE", "Current visual transition must keep full profile")
	_expect(
		(coordinator.last_patch.distribution_instances.unchanged as Array).size() > 0,
		"Stable population IDs must preserve genuinely unchanged instances"
	)
	_expect(c5.source_ir_revision == 0 and c5.authority == ChunkRecord.AuthorityState.COMMITTED, "Prompt must preserve Historical C5 IR0")

	var found_history_boundary := false
	for pair: Dictionary in runtime.last_boundary_plan.get("pairs", []):
		if (
			(pair.coord_a == C5 and pair.coord_b == C6)
			or (pair.coord_a == C6 and pair.coord_b == C5)
		):
			found_history_boundary = true
	_expect(found_history_boundary, "Historical IR0 | latest IR1 must produce a revision visual boundary")
	_expect(c5.source_ir_revision == 0, "Boundary reconciliation must not rewrite Historical source")

	var light_before := int(runtime.transition_mode_counts[SceneRuntime.TRANSITION_MODE_LIGHT_REBASE])
	var silent_before := int(runtime.transition_mode_counts[SceneRuntime.TRANSITION_MODE_SILENT])
	# Queue ordering reaches one diagonal/far Preview and then one cardinal
	# visible Preview. A remains in control and processes at most one per call.
	_expect(manager.process_preview_rebuilds(1) == 1, "First deferred Preview must process")
	_expect(manager.process_preview_rebuilds(1) == 1, "Second deferred Preview must process")
	_expect(
		int(runtime.transition_mode_counts[SceneRuntime.TRANSITION_MODE_SILENT]) > silent_before,
		"Far/diagonal Preview must use SILENT"
	)
	_expect(
		int(runtime.transition_mode_counts[SceneRuntime.TRANSITION_MODE_LIGHT_REBASE]) > light_before,
		"Visible cardinal Preview must use LIGHT_REBASE"
	)
	_expect(manager.process_preview_rebuilds(1) == 0, "LIGHT Preview must hold the single expensive scheduler slot")
	for _frame in range(60):
		if not bool(manager.debug_snapshot().preview_transition_in_flight):
			break
		await process_frame

	var c7_before := manager.get_record(C7)
	_expect(c7_before.source_ir_revision == 0 and c7_before.target_ir_revision == 1, "C7 must still be a stale latest-target Preview")
	_expect(manager.update_player_world_position(_position(C7)), "Entry barrier must update C7 before promotion")
	var c7 := manager.get_record(C7)
	_expect(c7.authority == ChunkRecord.AuthorityState.COMMITTED, "C7 must promote only after latest")
	_expect(c7.source_ir_revision == 1 and c7.target_ir_revision == 1, "C7 must be IR1 before formal entry")
	_expect(manager.get_record(C8) != null, "Moving to C7 must first materialize future C8")
	_expect(manager.get_record(C8).source_ir_revision == 1, "Never-materialized C8 must first generate from latest IR1")
	_expect(manager.update_player_world_position(_position(C8)), "Player must continue C7 -> C8")
	_expect(manager.get_record(C8).authority == ChunkRecord.AuthorityState.COMMITTED, "C8 must become Current COMMITTED")
	_expect(manager.get_record(C8).source_ir_revision == 1, "C8 Current must remain latest IR1")

	_expect(runtime.peak_candidate_scene_count <= 1, "Current + deferred Preview must not retain parallel Candidate scenes")
	_expect(runtime.candidate_scene_count == 0, "All Candidate scene ownership must be released")
	if failures == 0:
		print("Step 5 real A/B end-to-end tests passed")
	quit(1 if failures > 0 else 0)

func _wait_for_outcome(outcomes: Array[Dictionary]) -> Dictionary:
	for _frame in range(900):
		if not outcomes.is_empty():
			return outcomes[0]
		await process_frame
	_expect(false, "Timed out waiting for Current transaction")
	return {}

func _position(coord: Vector2i) -> Vector3:
	var origin := ChunkMath.chunk_origin(coord)
	return Vector3(origin.x + 80.0, 4.0, origin.y + 80.0)

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
			_distribution("trees", "tree", tree_count),
			_distribution("houses", "house", house_count),
		],
	}

func _distribution(id: String, semantic_type: String, count: int) -> Dictionary:
	return {
		"id": id,
		"type": semantic_type,
		"placement": {"relations": [{"type": "inside", "target": "forest"}]},
		"population": {
			"amount": {"mode": "count", "value": count},
			"arrangement": {"type": "uniform"},
		},
	}

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
