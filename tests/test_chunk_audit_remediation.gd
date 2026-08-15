extends SceneTree

func _init() -> void:
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	_test_initialize_retry(catalog)
	_test_ownership_environment_and_global_edges(catalog)
	_test_install_snapshot_and_boundary_copy(catalog)
	print("Chunk audit remediation tests passed")
	quit(0)

func _test_initialize_retry(catalog: PrototypeCatalog) -> void:
	var manager := ChunkManager.new()
	root.add_child(manager)
	manager.configure(catalog)
	var invalid := _base_ir()
	invalid["distributions"][0]["type"] = "missing_prototype"
	assert(not manager.initialize_world(invalid, 7, 1337))
	assert(manager.chunks.is_empty() and not manager.initialized)
	assert(manager.initialize_world(_base_ir(), 8, 1337))
	for record: ChunkRecord in manager.get_active_records():
		assert(record.source_ir_revision == 8 and record.target_ir_revision == 8)
	manager.free()

func _test_ownership_environment_and_global_edges(catalog: PrototypeCatalog) -> void:
	var generator := ChunkGenerator.new(catalog)
	var unique_ir := {
		"environment": {"fog_density": 0.25, "profile": "coastal"},
		"regions": [{"id": "graveyard", "type": "graveyard"}],
		"networks": [],
		"entities": [{"id": "church", "type": "church"}],
		"distributions": [{
			"id": "graves", "type": "tombstone",
			"placement": {"relations": [{"type": "inside", "target": "graveyard"}]},
			"population": {"amount": {"mode": "count", "value": 2}},
		}],
	}
	var owner := Vector2i(3, 2)
	var owned := generator.generate_chunk(owner, unique_ir, 1, 1337, null, {
		"transaction_chunk_coord": owner,
	})
	var distant := generator.generate_chunk(Vector2i(8, 8), unique_ir, 1, 1337, null, {
		"object_owner_coords": {"church": owner, "graveyard": owner},
	})
	assert(owned.find_entity("church") != null)
	assert(owned.find_region("graveyard") != null)
	assert(distant.find_entity("church") == null)
	assert(distant.find_region("graveyard") == null)
	assert(distant.distributions.is_empty())
	assert(owned.environment == unique_ir.environment)
	assert("environment" in JSON.parse_string(owned.deterministic_signature()))

	var fixture := _fixture_ir()
	var west := generator.generate_chunk(Vector2i.ZERO, fixture, 0, 1337)
	var east := generator.generate_chunk(Vector2i.RIGHT, fixture, 0, 1337)
	var size: int = west.terrain.grid_size
	for row in range(size):
		var west_index := row * size + size - 1
		var east_index := row * size
		assert(is_equal_approx(west.terrain.heights[west_index], east.terrain.heights[east_index]))
		assert(west.terrain.surface_masks[west_index].is_equal_approx(east.terrain.surface_masks[east_index]))
		assert(is_equal_approx(west.terrain.shore_wetness[west_index], east.terrain.shore_wetness[east_index]))

func _test_install_snapshot_and_boundary_copy(catalog: PrototypeCatalog) -> void:
	var manager := ChunkManager.new()
	root.add_child(manager)
	manager.configure(catalog)
	assert(manager.initialize_world(_base_ir(), 0, 1337))
	var coord := Vector2i.RIGHT
	var source := manager.get_record(coord)
	var bound_ir := {
		"regions": [{"id": "graveyard", "type": "graveyard"}],
		"networks": [], "entities": [], "distributions": [],
	}
	var overrides := {
		"transaction_chunk_coord": coord,
		"runtime_bindings": [{"ir_object_id": "graveyard", "runtime_fact_id": "area", "placement": "inside"}],
		"spatial_payloads": {"area": {"aabb2": {"x": 176.0, "z": 24.0, "w": 22.0, "d": 18.0}}},
	}
	var candidate := manager.generate_candidate(coord, bound_ir, 1, overrides)
	assert(candidate != null)
	manager.register_revision_ir(1, bound_ir)
	assert(manager.set_target_revision(coord, 1))
	assert(not manager.install_resolved_candidate(coord, candidate, 99, 1))
	assert(source.source_ir_revision == 0)
	assert(manager.install_resolved_candidate(coord, candidate, 0, 1))
	var signature := candidate.deterministic_signature()
	var polygon := candidate.find_region("graveyard").polygon.duplicate()
	assert(manager.unload_chunk(coord))
	var reloaded := manager.ensure_chunk(coord)
	assert(reloaded.resolved_chunk.deterministic_signature() == signature)
	assert(reloaded.resolved_chunk.find_region("graveyard").polygon == polygon)
	var constraints := manager.get_boundary_constraints(coord)
	constraints["north"] = {"terrain_heights": [999.0], "road_exits": []}
	assert(manager.get_boundary_constraints(coord) != constraints)
	manager.free()

func _base_ir() -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [], "entities": [],
		"distributions": [{
			"id": "trees", "type": "tree",
			"placement": {"relations": [{"type": "inside", "target": "forest"}]},
			"population": {"amount": {"mode": "count", "value": 2}, "arrangement": {"type": "uniform"}},
		}],
	}

func _fixture_ir() -> Dictionary:
	var file := FileAccess.open("res://data/fixtures/coastal_town_initial.json", FileAccess.READ)
	return JSON.parse_string(file.get_as_text()).world_ir
