extends SceneTree

const DEFAULT_OUTPUT := "res://test-results/artlab-performance.json"
const STREAM_PATH: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(2, 0),
	Vector2i(3, 1),
	Vector2i(4, 1),
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var output_path := DEFAULT_OUTPUT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")

	var fixture := _load_json("res://data/fixtures/coastal_town_initial.json")
	var world_ir: Dictionary = fixture.get("world_ir", {})
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var runtime := SceneRuntime.new()
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	manager.keep_dormant_mounted = false
	manager.eviction_radius = 2
	root.add_child(manager)
	manager.configure(catalog, runtime, world_root)

	var memory_before := _memory_snapshot()
	var start := Time.get_ticks_usec()
	var initialized := manager.initialize_world(world_ir, 0, 1337, _position(Vector2i.ZERO))
	var initialization_ms := _elapsed_ms(start)
	if not initialized:
		push_error("ArtLab benchmark initial 3x3 failed")
		quit(1)
		return
	await process_frame

	var revision_ir := world_ir.duplicate(true)
	for distribution: Dictionary in revision_ir.get("distributions", []):
		if String(distribution.get("id", "")) == "trees":
			distribution["population"] = {
				"amount": {"mode": "count", "value": 80},
				"arrangement": {"type": "clustered"},
			}
	start = Time.get_ticks_usec()
	var revision_candidate := manager.generate_candidate(Vector2i.ZERO, revision_ir, 1)
	var revision_candidate_ms := _elapsed_ms(start)
	if revision_candidate == null:
		push_error("ArtLab benchmark revision candidate failed")
		quit(1)
		return

	var streaming_ms: Array[float] = []
	for coord in STREAM_PATH:
		start = Time.get_ticks_usec()
		if not manager.update_player_world_position(_position(coord)):
			push_error("ArtLab benchmark streaming failed at %s" % coord)
			quit(1)
			return
		streaming_ms.append(_elapsed_ms(start))
		await process_frame

	var high_density_ir := {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [{"id": "road", "type": "road", "topology": {"from": "south", "to": "north"}}],
		"entities": [],
		"distributions": [{
			"id": "trees",
			"type": "tree",
			"placement": {"relations": [{"type": "inside", "target": "forest"}]},
			"population": {"amount": {"mode": "count", "value": 400}, "arrangement": {"type": "random"}},
		}],
	}
	start = Time.get_ticks_usec()
	var dense_chunk := ChunkGenerator.new(catalog).generate_chunk(Vector2i.ZERO, high_density_ir, 0, 4242)
	var high_density_ms := _elapsed_ms(start)
	if not dense_chunk.errors.is_empty():
		push_error("ArtLab benchmark high-density generation failed: %s" % " | ".join(dense_chunk.errors))
		quit(1)
		return

	var frame_ms: Array[float] = []
	for _index in range(90):
		start = Time.get_ticks_usec()
		await process_frame
		frame_ms.append(_elapsed_ms(start))
	frame_ms.sort()

	var metrics := _world_metrics(manager)
	var report := {
		"format": "worldir-godot-artlab-performance-v1",
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_video_adapter_name(),
		"policy_fingerprint": RealizationPolicy.new().fingerprint(),
		"initial_3x3_ms": initialization_ms,
		"single_chunk_revision_candidate_ms": revision_candidate_ms,
		"streaming_move_ms": streaming_ms,
		"streaming_move_average_ms": _average(streaming_ms),
		"high_density_chunk_ms": high_density_ms,
		"high_density_explicit_instances": dense_chunk.find_distribution("trees").instances.size(),
		"high_density_decorations": _decoration_count(dense_chunk),
		"frame_time_ms": {
			"average": _average(frame_ms),
			"p95": frame_ms[clampi(int(ceil(float(frame_ms.size()) * 0.95)) - 1, 0, frame_ms.size() - 1)],
			"maximum": frame_ms[-1],
		},
		"active_world": metrics,
		"memory_before": memory_before,
		"memory_after": _memory_snapshot(),
	}
	if not _write_json(output_path, report):
		quit(1)
		return
	print("ARTLAB_PERFORMANCE %s" % JSON.stringify(report))
	manager.free()
	world_root.free()
	runtime.free()
	catalog.free()
	quit(0)

func _world_metrics(manager: ChunkManager) -> Dictionary:
	var result := {"active_chunks": 0, "entities": 0, "distribution_instances": 0, "decorations": 0}
	for record: ChunkRecord in manager.get_active_records():
		var chunk := record.resolved_chunk
		if chunk == null:
			continue
		result.active_chunks += 1
		result.entities += chunk.entities.size()
		for distribution: ResolvedDistribution in chunk.distributions:
			result.distribution_instances += distribution.instances.size()
		result.decorations += _decoration_count(chunk)
	return result

func _decoration_count(chunk: ResolvedChunk) -> int:
	var result := 0
	for decoration: ResolvedDecoration in chunk.decorations:
		result += decoration.instances.size()
	return result

func _memory_snapshot() -> Dictionary:
	return {
		"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"static_max_bytes": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
	}

func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0

func _position(coord: Vector2i) -> Vector3:
	var origin := ChunkMath.chunk_origin(coord)
	return Vector3(origin.x + 80.0, 4.0, origin.y + 80.0)

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _write_json(path: String, value: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		push_error("Could not create benchmark directory: %s" % absolute.get_base_dir())
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write benchmark: %s" % path)
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return true
