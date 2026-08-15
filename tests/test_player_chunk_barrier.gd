extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerController
	root.add_child(player)
	await process_frame
	player.global_position = Vector3(159.5, 5.0, 80.0)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	root.add_child(manager)
	manager.configure(catalog, null, null, player)
	var valid_ir := _ir("tree")
	assert(manager.initialize_world(valid_ir, 0, 1337, player.global_position))
	player.set_chunk_manager(manager)
	var invalid_ir := _ir("missing_prototype")
	manager.register_revision_ir(1, invalid_ir)
	assert(manager.set_target_revision(Vector2i.RIGHT, 1))
	player.velocity = Vector3(8.0, 0.0, 0.0)
	assert(not player._move_with_chunk_gate(1.0))
	assert(ChunkMath.world_to_chunk(player.global_position) == manager.get_current_chunk_coord())
	assert(manager.get_record(Vector2i.RIGHT).is_stale)
	print("Player Chunk entry barrier tests passed")
	quit(0)

func _ir(distribution_type: String) -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [], "entities": [],
		"distributions": [{
			"id": "trees", "type": distribution_type,
			"placement": {"relations": [{"type": "inside", "target": "forest"}]},
			"population": {"amount": {"mode": "count", "value": 1}},
		}],
	}
