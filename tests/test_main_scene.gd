extends SceneTree

var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var scene := load("res://scenes/main.tscn") as PackedScene
    _expect(scene != null, "Main scene must load")
    if scene == null:
        quit(1)
        return
    var main := scene.instantiate() as Node3D
    var coordinator := main.get_node("WorldCoordinator") as WorldCoordinator
    coordinator.use_http_compiler = false
    coordinator.auto_generate_demo = true
    # PromptPanel intentionally resolves through SceneTree.current_scene, which
    # is not populated when a test manually attaches an instance under root.
    main.get_node("UI").free()
    root.add_child(main)
    await process_frame
    await process_frame
    _expect(coordinator.current_resolved != null, "Fake compiler must commit the demo world")
    if coordinator.current_resolved != null:
        _expect(coordinator.current_resolved.terrain != null, "Committed demo must include resolved terrain")
        var manager := main.get_node("ChunkManager") as ChunkManager
        _expect(manager.initialized, "Main scene must initialize the real ChunkManager")
        _expect(manager.get_active_records().size() == 9, "Main scene must materialize a 3x3 window")
        var current_coord := manager.get_current_chunk_coord()
        var chunk_root := manager.get_chunk_root(current_coord)
        _expect(chunk_root != null, "Current ChunkRoot must be mounted")
        _expect(chunk_root.get_node_or_null("GeneratedWorld/Terrain/WorldSurface") != null, "Committed Chunk scene must contain the world surface")
        _expect(main.get_node_or_null("BaseGround") == null, "Legacy flat base ground must stay removed")
        var generated := chunk_root.get_node("GeneratedWorld") as Node3D
        var tree_group := generated.get_node("Distributions/trees")
        var stable_tree := tree_group.get_child(0) as Node3D
        var stable_terrain := generated.get_node("Terrain/WorldSurface") as Node3D
        var stable_road := generated.get_node("Networks/main_road") as Node3D
        var generated_id := generated.get_instance_id()
        var tree_id := stable_tree.get_instance_id()
        var terrain_id := stable_terrain.get_instance_id()
        var road_id := stable_road.get_instance_id()
        coordinator.scene_runtime.scene_transition.duration_scale = 0.02
        coordinator.submit_prompt("保持当前世界不变")
        for _frame in range(120):
            if not coordinator.busy:
                break
            await process_frame
        var rewritten := manager.get_chunk_root(current_coord).get_node("GeneratedWorld") as Node3D
        _expect(
            rewritten.get_instance_id() == generated_id,
            "No-op edit must preserve the active Chunk GeneratedWorld Node"
        )
        _expect(
            (rewritten.get_node("Distributions/trees").get_child(0) as Node3D).get_instance_id() == tree_id,
            "No-op edit must preserve unchanged instance identity"
        )
        _expect(
            (rewritten.get_node("Terrain/WorldSurface") as Node3D).get_instance_id() == terrain_id,
            "No-op edit must preserve unchanged terrain identity"
        )
        _expect(
            (rewritten.get_node("Networks/main_road") as Node3D).get_instance_id() == road_id,
            "No-op edit must preserve unchanged road identity"
        )
        _expect(
            not coordinator.scene_runtime.scene_transition.last_patch_summary.ripple_spawned,
            "No-op edit must not play rewrite feedback"
        )
    main.free()
    if failures == 0:
        print("Main scene smoke test passed")
    quit(1 if failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
