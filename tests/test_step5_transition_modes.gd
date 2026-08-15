extends SceneTree

var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var runtime := SceneRuntime.new()
	runtime.prototype_catalog = catalog
	runtime.scene_transition.duration_scale = 0.0
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var generator := ChunkGenerator.new(catalog)
	var ir0 := _world_ir(10, 2)
	var ir1 := _world_ir(5, 6)

	var current_coord := Vector2i.ZERO
	var current_old := generator.generate_chunk(current_coord, ir0, 0, 7301)
	var current_new := generator.generate_chunk(current_coord, ir1, 1, 7301)
	var current_root := runtime.get_or_create_chunk_root(world_root, current_coord)
	_expect(runtime.mount_chunk(current_root, current_old) != null, "Current must mount")

	var neighbor_coord := Vector2i.RIGHT
	var neighbor_old := generator.generate_chunk(neighbor_coord, ir0, 0, 7301)
	var neighbor_new := generator.generate_chunk(neighbor_coord, ir1, 1, 7301)
	var neighbor_root := runtime.get_or_create_chunk_root(world_root, neighbor_coord)
	_expect(runtime.mount_chunk(neighbor_root, neighbor_old) != null, "Neighbor must mount")
	var neighbor_scene_id := neighbor_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME).get_instance_id()

	var full_result := await runtime.transition_chunk(
		current_root,
		current_old,
		current_new,
		SceneRuntime.TRANSITION_MODE_FULL_REWRITE
	)
	_expect(full_result.ok, "FULL_REWRITE must succeed")
	_expect(
		runtime.last_transition_mode_by_coord[current_coord] == SceneRuntime.TRANSITION_MODE_FULL_REWRITE,
		"Transaction Current must use FULL_REWRITE"
	)
	_expect(runtime.scene_transition.last_patch_summary.ripple_spawned, "FULL_REWRITE must keep ripple feedback")
	_expect(
		neighbor_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME).get_instance_id() == neighbor_scene_id,
		"Current transition must not mutate neighbor ChunkRoot"
	)

	var light_result := await runtime.transition_chunk(
		neighbor_root,
		neighbor_old,
		neighbor_new,
		SceneRuntime.TRANSITION_MODE_LIGHT_REBASE
	)
	_expect(light_result.ok, "LIGHT_REBASE must succeed")
	_expect(
		runtime.scene_transition.last_patch_summary.tween_strategy == "single_group_crossfade",
		"LIGHT_REBASE must use one group crossfade"
	)
	_expect(
		int(runtime.scene_transition.last_patch_summary.estimated_tween_count) == 1,
		"LIGHT_REBASE must not allocate per-object complex Tweens"
	)
	_expect(not runtime.scene_transition.last_patch_summary.ripple_spawned, "LIGHT_REBASE must not spawn rewrite ripple")

	var far_coord := Vector2i(1, 1)
	var far_old := generator.generate_chunk(far_coord, ir0, 0, 7301)
	var far_new := generator.generate_chunk(far_coord, ir1, 1, 7301)
	var far_root := runtime.get_or_create_chunk_root(world_root, far_coord)
	_expect(runtime.mount_chunk(far_root, far_old) != null, "Far Preview must mount")
	var effects_before := far_root.get_node_or_null("GeneratedWorld/Effects")
	var silent_result := await runtime.transition_chunk(
		far_root,
		far_old,
		far_new,
		SceneRuntime.TRANSITION_MODE_SILENT
	)
	_expect(silent_result.ok, "SILENT must succeed")
	_expect(
		runtime.last_transition_mode_by_coord[far_coord] == SceneRuntime.TRANSITION_MODE_SILENT,
		"Far Preview must record canonical SILENT mode"
	)
	_expect(effects_before == null and far_root.get_node_or_null("GeneratedWorld/Effects") == null, "SILENT must not create rewrite effects")

	_expect(
		runtime.preview_transition_mode(current_coord, neighbor_coord, neighbor_root)
			== SceneRuntime.TRANSITION_MODE_LIGHT_REBASE,
		"Visible cardinal Preview must select LIGHT_REBASE"
	)
	_expect(
		runtime.preview_transition_mode(current_coord, far_coord, far_root)
			== SceneRuntime.TRANSITION_MODE_SILENT,
		"Diagonal/far Preview must select SILENT"
	)
	far_root.visible = false
	_expect(
		runtime.preview_transition_mode(current_coord, neighbor_coord, far_root)
			== SceneRuntime.TRANSITION_MODE_SILENT,
		"Invisible Preview must select SILENT"
	)
	_expect(runtime.candidate_scene_count == 0, "All Candidate scenes must leave PREPARE ownership")
	_expect(runtime.peak_candidate_scene_count == 1, "Sequential paths must keep only one Candidate scene prepared")

	if failures == 0:
		print("Step 5 transition mode tests passed")
	quit(1 if failures > 0 else 0)

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

func _distribution(id: String, type: String, count: int) -> Dictionary:
	return {
		"id": id,
		"type": type,
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
