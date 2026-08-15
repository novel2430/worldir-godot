extends SceneTree

var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var state := WorldState.new()
	root.add_child(state)
	state.commit(_world_ir(10), [])
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var runtime := SceneRuntime.new()
	runtime.scene_transition.duration_scale = 0.1
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	root.add_child(manager)
	manager.configure(catalog, runtime, world_root)
	_expect(manager.initialize_world(state.current_ir, 0, 7301), "Real A must initialize")
	manager.set_process(false)
	var preview_coord := Vector2i.RIGHT
	var preview := manager.get_record(preview_coord)
	var completed_revisions: Array[int] = []
	manager.preview_rebuild_completed.connect(func(_coord: Vector2i, revision: int):
		completed_revisions.append(revision)
	)

	state.commit(_world_ir(7), [])
	manager.set_generation_context(state.current_ir, 1)
	_expect(manager.set_target_revision(preview_coord, 1), "IR1 target must install")
	_expect(manager.request_rebuild(preview_coord, 1), "IR1 rebuild must queue")
	state.commit(_world_ir(3), [])
	manager.set_generation_context(state.current_ir, 2)
	_expect(manager.set_target_revision(preview_coord, 2), "IR2 target must supersede IR1")
	_expect(manager.request_rebuild(preview_coord, 2), "IR2 rebuild must replace queued IR1")
	_expect(preview.source_ir_revision == 0 and preview.target_ir_revision == 2, "Preview must remain stale directly for latest IR2")
	_expect(_queued_revision(manager.debug_snapshot(), preview_coord) == 2, "A queue must retain only latest target")

	_expect(manager.process_preview_rebuilds(1) == 1, "Real A must process one Preview")
	_expect(preview.source_ir_revision == 2 and not preview.is_stale, "Preview must install IR2 without replay")
	_expect(completed_revisions == [2], "Only latest revision may complete")
	_expect(
		runtime.last_transition_mode_by_coord[preview_coord] == SceneRuntime.TRANSITION_MODE_LIGHT_REBASE,
		"Visible cardinal Preview must use LIGHT_REBASE"
	)
	_expect(manager.process_preview_rebuilds(1) == 0, "A must not start another expensive Preview during LIGHT overlap")
	for _frame in range(30):
		if not bool(manager.debug_snapshot().preview_transition_in_flight):
			break
		await process_frame
	_expect(not bool(manager.debug_snapshot().preview_transition_in_flight), "LIGHT overlap must release scheduler slot")

	# A committed global revision is never rolled back by a later Preview
	# generation failure. Overwrite only A's registered test input to force the
	# failure domain without changing WorldState revision 2.
	var failing_coord := Vector2i(0, -1)
	var failing_record := manager.get_record(failing_coord)
	var invalid_ir: Dictionary = state.current_ir.duplicate(true)
	invalid_ir.distributions[0].type = "missing_prototype"
	manager.register_revision_ir(2, invalid_ir)
	_expect(manager.set_target_revision(failing_coord, 2), "Failure Preview target must remain latest IR2")
	_expect(manager.request_rebuild(failing_coord, 2), "Failure Preview must queue")
	_expect(manager.process_preview_rebuilds(1) == 1, "Failure work item must be consumed")
	_expect(state.current_ir_revision == 2, "Preview failure must not roll back committed global revision")
	_expect(failing_record.source_ir_revision == 0 and failing_record.target_ir_revision == 2, "Failed Preview must remain stale for retry")

	_expect(runtime.peak_candidate_scene_count <= 1, "Deferred scheduler must not retain multiple prepared Candidate scenes")
	if failures == 0:
		print("Step 5 real Preview scheduler tests passed")
	quit(1 if failures > 0 else 0)

func _queued_revision(snapshot: Dictionary, coord: Vector2i) -> int:
	for record: Dictionary in snapshot.records:
		if record.coord == [coord.x, coord.y]:
			return int(record.queued_revision)
	return -1

func _world_ir(tree_count: int) -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [],
		"entities": [],
		"distributions": [{
			"id": "trees",
			"type": "tree",
			"placement": {"relations": [{"type": "inside", "target": "forest"}]},
			"population": {
				"amount": {"mode": "count", "value": tree_count},
				"arrangement": {"type": "uniform"},
			},
		}],
	}

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
