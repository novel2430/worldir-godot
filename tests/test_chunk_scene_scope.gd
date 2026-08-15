extends SceneTree

var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var runtime := SceneRuntime.new()
	root.add_child(runtime)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var generator := ChunkGenerator.new(catalog)
	var ir0 := _simple_ir(6)
	var ir1 := _simple_ir(2)
	var old_target := generator.generate_chunk(Vector2i.ZERO, ir0, 0, 1337)
	var new_target := generator.generate_chunk(Vector2i.ZERO, ir1, 1, 1337)
	var neighbor := generator.generate_chunk(Vector2i.RIGHT, ir0, 0, 1337)
	var target_root := runtime.get_or_create_chunk_root(world_root, Vector2i.ZERO)
	var neighbor_root := runtime.get_or_create_chunk_root(world_root, Vector2i.RIGHT)
	_expect(runtime.mount_chunk(target_root, old_target, catalog) != null, "Target Chunk must mount")
	_expect(runtime.mount_chunk(neighbor_root, neighbor, catalog) != null, "Neighbor Chunk must mount")
	var neighbor_world := neighbor_root.get_node("GeneratedWorld") as Node3D
	var neighbor_instance_id := neighbor_world.get_instance_id()
	var sentinel := Node3D.new()
	sentinel.name = "SentinelRuntimeNode"
	target_root.add_child(sentinel)
	var sentinel_id := sentinel.get_instance_id()
	var result: Dictionary = await runtime.transition_chunk(
		target_root, old_target, new_target, &"SILENT_REBUILD", catalog
	)
	_expect(bool(result.get("ok", false)), "Chunk-scoped silent transition must succeed")
	_expect(int(target_root.get_meta("ir_revision")) == 1, "Target root revision must advance")
	_expect(
		target_root.get_node("SentinelRuntimeNode").get_instance_id() == sentinel_id,
		"SILENT_REBUILD must preserve stable runtime children"
	)
	_expect(
		(neighbor_root.get_node("GeneratedWorld") as Node3D).get_instance_id() == neighbor_instance_id,
		"Transitioning one Chunk must not mutate its neighbor root"
	)
	world_root.free()
	runtime.free()
	catalog.free()
	if failures == 0:
		print("Chunk-scoped SceneRuntime tests passed")
	quit(1 if failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _simple_ir(tree_count: int) -> Dictionary:
	return {
		"regions": [{"id": "forest", "type": "forest"}],
		"networks": [{
			"id": "main_road", "type": "road",
			"topology": {"from": "south", "to": "north"},
		}],
		"entities": [],
		"distributions": [{
			"id": "trees", "type": "tree",
			"placement": {"relations": [{"type": "inside", "target": "forest"}]},
			"population": {
				"amount": {"mode": "count", "value": tree_count},
				"arrangement": {"type": "uniform"},
			},
		}],
	}
