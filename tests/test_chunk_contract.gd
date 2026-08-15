extends SceneTree

func _init() -> void:
	_test_coordinates()
	_test_record_contract()
	_test_boundary_contract()
	print("Chunk shared contract tests passed")
	quit(0)

func _test_coordinates() -> void:
	assert(ChunkMath.CHUNK_SIZE_M == 160.0)
	assert(ChunkMath.ACTIVE_RADIUS == 1)
	assert(ChunkMath.world_to_chunk(Vector3(0.0, 0.0, 0.0)) == Vector2i(0, 0))
	assert(ChunkMath.world_to_chunk(Vector3(159.9, 0.0, 0.0)) == Vector2i(0, 0))
	assert(ChunkMath.world_to_chunk(Vector3(160.0, 0.0, 0.0)) == Vector2i(1, 0))
	assert(ChunkMath.world_to_chunk(Vector3(-0.1, 0.0, 0.0)) == Vector2i(-1, 0))
	assert(ChunkMath.world_to_chunk(Vector3(-160.0, 0.0, 0.0)) == Vector2i(-1, 0))
	assert(ChunkMath.world_to_chunk(Vector3(-160.1, 0.0, 0.0)) == Vector2i(-2, 0))
	assert(ChunkMath.chunk_origin(Vector2i(-2, 3)) == Vector2(-320.0, 480.0))
	assert(ChunkMath.chunk_bounds(Vector2i(1, -1)) == Rect2(160.0, -160.0, 160.0, 160.0))
	assert(ChunkMath.active_window_coords(Vector2i(5, 6)).size() == 9)
	assert(ChunkMath.is_in_active_window(Vector2i(4, 5), Vector2i(5, 6)))
	assert(not ChunkMath.is_in_active_window(Vector2i(3, 6), Vector2i(5, 6)))

func _test_record_contract() -> void:
	var record := ChunkRecord.new().configure(Vector2i(2, -3), 0, 0)
	assert(not record.is_stale)
	assert(record.authority == ChunkRecord.AuthorityState.PROVISIONAL)
	record.set_target_revision(1)
	assert(record.is_stale)
	var resolved := ResolvedChunk.new()
	resolved.coord = record.coord
	resolved.revision = 1
	record.accept_resolved(resolved)
	assert(not record.is_stale)
	assert(record.source_ir_revision == 1)
	assert(record.target_ir_revision == 1)

func _test_boundary_contract() -> void:
	var constraints := ChunkBoundaryConstraints.new()
	constraints.set_terrain_heights("west", PackedFloat32Array([1.0, 2.0]))
	constraints.add_road_exit("west", {
		"id": "main_road",
		"position": Vector2(160.0, 80.0),
		"tangent": Vector2.RIGHT,
		"width": 4.2,
	})
	assert(constraints.terrain_heights("west") == PackedFloat32Array([1.0, 2.0]))
	assert(constraints.road_exits("west").size() == 1)
	var copy := constraints.duplicate_constraints()
	copy.set_terrain_heights("west", PackedFloat32Array([3.0]))
	assert(constraints.terrain_heights("west").size() == 2)
