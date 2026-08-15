extends SceneTree

var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/chunk_streaming_demo.tscn") as PackedScene
	_expect(packed != null, "Chunk streaming demo scene must load")
	if packed == null:
		quit(1)
		return
	var demo := packed.instantiate()
	root.add_child(demo)
	await process_frame
	var manager := demo.get_node("ChunkManager") as ChunkManager
	_expect(manager.initialized, "Chunk demo must initialize the manager")
	_expect(manager.get_active_records().size() == 9, "Chunk demo must materialize a 3x3 window")
	_expect(
		demo.get_node_or_null("WorldRoot/Chunks/Chunk_0_0/GeneratedWorld/Terrain/WorldSurface") != null,
		"Chunk demo center terrain must be mounted under a scoped Chunk root"
	)
	_expect("Current Chunk: (0,0)" in demo.debug_label.text, "Debug overlay must show current Chunk")
	_expect("source=" in demo.debug_label.text, "Debug overlay must show revision routing")
	var stable_root := manager.get_chunk_root(Vector2i.ZERO)
	_expect(stable_root != null, "Manager must expose a stable Chunk handle")
	_expect(
		manager.update_player_world_position(Vector3(80.0, 7.0, -80.0)),
		"Player must cross north into the next Chunk"
	)
	_expect(
		manager.update_player_world_position(Vector3(80.0, 7.0, -240.0)),
		"Player must cross north a second time"
	)
	_expect(manager.get_current_chunk_coord() == Vector2i(0, -2), "Current Chunk must follow two crossings")
	_expect(manager.get_active_records().size() == 9, "3x3 window must roll after crossings")
	_expect(
		demo.get_node_or_null("WorldRoot/Chunks/Chunk_0_-3/GeneratedWorld") != null,
		"Rolled window must mount newly visible northern Chunks"
	)
	demo.free()
	if failures == 0:
		print("Chunk streaming demo scene smoke test passed")
	quit(1 if failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
