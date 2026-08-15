extends SceneTree

const PATH: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(1, 0),
	Vector2i(2, 0),
	Vector2i(3, 1),
	Vector2i(4, 1),
	Vector2i(5, 2),
]

func _init() -> void:
	var fixture := _load_json("res://data/fixtures/inland_forest_village.json")
	var ir: Dictionary = fixture.get("world_ir", {})
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	manager.keep_dormant_mounted = false
	manager.eviction_radius = 2
	root.add_child(manager)
	manager.configure(catalog)
	assert(manager.initialize_world(ir, 0, 9917, _position(PATH[0])))
	var origin_signature := manager.get_record(Vector2i.ZERO).resolved_chunk.deterministic_signature()

	for coord in PATH.slice(1):
		assert(manager.update_player_world_position(_position(coord)))
		assert(manager.get_active_records().size() == 9)
		_assert_active_seams(manager)

	var origin_record := manager.get_record(Vector2i.ZERO)
	assert(origin_record != null)
	assert(origin_record.authority == ChunkRecord.AuthorityState.COMMITTED)
	assert(origin_record.source_ir_revision == 0)
	assert(origin_record.streaming_state == ChunkRecord.StreamingState.UNLOADED)
	assert(manager.update_player_world_position(_position(Vector2i.ZERO)))
	assert(manager.get_record(Vector2i.ZERO).resolved_chunk.deterministic_signature() == origin_signature)
	_assert_active_seams(manager)

	manager.free()
	catalog.free()
	print("ArtLab streaming scale tests passed")
	quit(0)

func _assert_active_seams(manager: ChunkManager) -> void:
	for record: ChunkRecord in manager.get_active_records():
		for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor := manager.get_record(record.coord + offset)
			if neighbor == null or neighbor.resolved_chunk == null:
				continue
			_assert_terrain_edge(record.resolved_chunk, neighbor.resolved_chunk, offset)

func _assert_terrain_edge(a: ResolvedChunk, b: ResolvedChunk, offset: Vector2i) -> void:
	var size: int = a.terrain.grid_size
	assert(size == b.terrain.grid_size)
	for index in range(size):
		var a_index: int
		var b_index: int
		if offset == Vector2i.RIGHT:
			a_index = index * size + size - 1
			b_index = index * size
		else:
			a_index = (size - 1) * size + index
			b_index = index
		assert(is_equal_approx(a.terrain.heights[a_index], b.terrain.heights[b_index]))
		assert(a.terrain.surface_masks[a_index].is_equal_approx(b.terrain.surface_masks[b_index]))
		assert(is_equal_approx(a.terrain.shore_wetness[a_index], b.terrain.shore_wetness[b_index]))

func _position(coord: Vector2i) -> Vector3:
	var origin := ChunkMath.chunk_origin(coord)
	return Vector3(origin.x + 80.0, 4.0, origin.y + 80.0)

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
