extends SceneTree

var catalog: PrototypeCatalog
var manager: ChunkManager
var ir0: Dictionary
var ir1: Dictionary
var changed_events: Array = []

func _init() -> void:
	catalog = PrototypeCatalog.new()
	root.add_child(catalog)
	manager = ChunkManager.new()
	root.add_child(manager)
	manager.current_chunk_changed.connect(func(old_coord: Vector2i, new_coord: Vector2i):
		changed_events.append([old_coord, new_coord])
	)
	manager.configure(catalog)
	ir0 = _simple_ir(8)
	ir1 = _simple_ir(3)
	_test_initial_active_window()
	_test_transaction_pin()
	_test_provisional_rebuild_contract()
	_test_no_stale_entry_and_window_shift()
	_test_historical_reload_preservation()
	_test_future_uses_latest()
	_test_revision_coalescing()
	_test_debug_observability()
	_test_scene_mount_unmount()
	print("ChunkManager lifecycle tests passed")
	quit(0)

func _test_initial_active_window() -> void:
	assert(manager.initialize_world(ir0, 0, 1337, Vector3(20.0, 3.0, 20.0)))
	assert(manager.get_current_chunk_coord() == Vector2i.ZERO)
	assert(manager.get_active_records().size() == 9)
	for record: ChunkRecord in manager.get_active_records():
		assert(record.resolved_chunk != null)
		assert(not record.is_stale)
		if record.coord == Vector2i.ZERO:
			assert(record.streaming_state == ChunkRecord.StreamingState.ACTIVE)
			assert(record.authority == ChunkRecord.AuthorityState.COMMITTED)
		else:
			assert(record.streaming_state == ChunkRecord.StreamingState.ENVIRONMENT_READY)
			assert(record.authority == ChunkRecord.AuthorityState.PROVISIONAL)

func _test_transaction_pin() -> void:
	var coord := Vector2i(1, 1)
	var record := manager.get_record(coord)
	assert(manager.pin_chunk(coord))
	assert(manager.is_chunk_pinned(coord))
	assert(not manager.unload_chunk(coord))
	assert(record.resolved_chunk != null)
	assert(manager.unpin_chunk(coord))
	assert(not manager.is_chunk_pinned(coord))

func _test_provisional_rebuild_contract() -> void:
	var coord := Vector2i(1, 0)
	var record := manager.get_record(coord)
	var old_signature := record.resolved_chunk.deterministic_signature()
	var candidate := manager.generate_candidate(coord, ir1, 1)
	assert(candidate != null)
	# PREPARE cannot publish candidate metadata to the formal record.
	assert(record.source_ir_revision == 0)
	assert(record.target_ir_revision == 0)
	assert(not record.is_stale)
	manager.register_revision_ir(1, ir1)
	assert(manager.set_target_revision(coord, 1))
	assert(record.source_ir_revision == 0)
	assert(record.target_ir_revision == 1)
	assert(record.is_stale)
	assert(candidate.revision == 1)
	# Candidate generation is not an implicit Revision commit.
	assert(record.source_ir_revision == 0)
	assert(record.is_stale)
	assert(candidate.deterministic_signature() != old_signature)
	assert(manager.accept_rebuild(coord, candidate, false))
	assert(record.source_ir_revision == 1)
	assert(record.target_ir_revision == 1)
	assert(not record.is_stale)

func _test_revision_coalescing() -> void:
	var coord := Vector2i(1, -1)
	var record := manager.get_record(coord)
	var ir3 := _simple_ir(2)
	manager.register_revision_ir(3, ir3)
	assert(manager.set_target_revision(coord, 3))
	assert(manager.request_rebuild(coord, 3))
	var ir4 := _simple_ir(1)
	manager.register_revision_ir(4, ir4)
	assert(manager.set_target_revision(coord, 4))
	assert(manager.request_rebuild(coord, 4))
	assert(manager.process_preview_rebuilds(1) == 1)
	assert(record.source_ir_revision == 4)
	assert(record.target_ir_revision == 4)
	assert(not record.is_stale)

func _test_no_stale_entry_and_window_shift() -> void:
	manager.set_generation_context(ir1, 1)
	var target := Vector2i(0, -1)
	manager.set_target_revision(target, 1)
	assert(manager.get_record(target).is_stale)
	assert(manager.update_player_world_position(Vector3(20.0, 3.0, -20.0)))
	assert(manager.get_current_chunk_coord() == target)
	assert(changed_events == [[Vector2i.ZERO, target]])
	var current := manager.get_record(target)
	assert(current.authority == ChunkRecord.AuthorityState.COMMITTED)
	assert(current.streaming_state == ChunkRecord.StreamingState.ACTIVE)
	assert(current.source_ir_revision == 1)
	assert(current.target_ir_revision == 1)
	assert(not current.is_stale)
	var history := manager.get_record(Vector2i.ZERO)
	assert(history.authority == ChunkRecord.AuthorityState.COMMITTED)
	assert(history.source_ir_revision == 0)
	assert(manager.get_active_records().size() == 9)

func _test_future_uses_latest() -> void:
	var future := manager.get_record(Vector2i(0, -2))
	assert(future != null)
	assert(future.authority == ChunkRecord.AuthorityState.PROVISIONAL)
	assert(future.source_ir_revision == 1)
	assert(future.target_ir_revision == 1)

	var invalid_ir := ir1.duplicate(true)
	invalid_ir["distributions"][0]["type"] = "missing_prototype"
	manager.register_revision_ir(2, invalid_ir)
	var blocked_coord := Vector2i(1, -1)
	manager.set_target_revision(blocked_coord, 2)
	assert(not manager.update_player_world_position(Vector3(180.0, 3.0, -20.0)))
	assert(manager.get_current_chunk_coord() == Vector2i(0, -1))
	assert(manager.get_record(blocked_coord).is_stale)

func _test_historical_reload_preservation() -> void:
	var history_coord := Vector2i.ZERO
	var history := manager.get_record(history_coord)
	assert(history.authority == ChunkRecord.AuthorityState.COMMITTED)
	assert(history.source_ir_revision == 0 and history.target_ir_revision == 0)
	var signature := history.resolved_chunk.deterministic_signature()
	assert(manager.unload_chunk(history_coord))
	assert(history.resolved_chunk == null)
	var reloaded := manager.ensure_chunk(history_coord)
	assert(reloaded != null)
	assert(reloaded.source_ir_revision == 0 and reloaded.target_ir_revision == 0)
	assert(reloaded.resolved_chunk.deterministic_signature() == signature)

func _test_debug_observability() -> void:
	var snapshot := manager.debug_snapshot()
	assert(snapshot["current_chunk_coord"] == [0, -1])
	assert(snapshot["current_ir_revision"] == 1)
	assert((snapshot["active_coords"] as Array).size() == 9)
	var text := manager.debug_text()
	assert("Current Chunk: (0,-1)" in text)
	assert("source=" in text and "target=" in text and "stale=" in text)

func _test_scene_mount_unmount() -> void:
	var runtime := SceneRuntime.new()
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var record := manager.get_record(manager.get_current_chunk_coord())
	var chunk_root := runtime.get_or_create_chunk_root(world_root, record.coord)
	var mounted := runtime.mount_chunk(chunk_root, record.resolved_chunk, catalog)
	assert(mounted != null)
	assert(runtime.get_mounted_chunk(world_root, record.coord) == mounted)
	assert(mounted.get_node_or_null("GeneratedWorld/Terrain/WorldSurface") != null)
	runtime.unmount_chunk(world_root, record.coord)
	assert(runtime.get_mounted_chunk(world_root, record.coord) == null)

func _simple_ir(tree_count: int) -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [{
			"id": "main_road",
			"type": "road",
			"topology": {"from": "south", "to": "north"},
		}],
		"entities": [],
		"distributions": [{
			"id": "trees",
			"type": "tree",
			"placement": {
				"relations": [{"type": "inside", "target": "forest"}],
			},
			"population": {
				"amount": {"mode": "count", "value": tree_count},
				"arrangement": {"type": "uniform"},
			},
		}],
	}
