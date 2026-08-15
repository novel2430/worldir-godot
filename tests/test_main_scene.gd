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
        _expect(main.get_node_or_null("WorldRoot/GeneratedWorld/Terrain/WorldSurface") != null, "Committed scene must contain the world surface")
        _expect(main.get_node_or_null("BaseGround") == null, "Legacy flat base ground must stay removed")
        var generated := main.get_node("WorldRoot/GeneratedWorld") as Node3D
        var stable_tree := generated.get_node("Distributions/coastal_trees/coastal_trees_000") as Node3D
        var stable_terrain := generated.get_node("Terrain/WorldSurface") as Node3D
        var stable_road := generated.get_node("Networks/main_path") as Node3D
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
        _expect(not coordinator.busy, "No-op edit must finish")
        _expect(
            (main.get_node("WorldRoot/GeneratedWorld") as Node3D).get_instance_id() == generated_id,
            "No-op edit must preserve the active GeneratedWorld Node"
        )
        _expect(
            (main.get_node("WorldRoot/GeneratedWorld/Distributions/coastal_trees/coastal_trees_000") as Node3D).get_instance_id() == tree_id,
            "No-op edit must preserve unchanged instance identity"
        )
        _expect(
            (main.get_node("WorldRoot/GeneratedWorld/Terrain/WorldSurface") as Node3D).get_instance_id() == terrain_id,
            "No-op edit must preserve unchanged terrain identity"
        )
        _expect(
            (main.get_node("WorldRoot/GeneratedWorld/Networks/main_path") as Node3D).get_instance_id() == road_id,
            "No-op edit must preserve unchanged road identity"
        )
        _expect(
            not coordinator.scene_runtime.scene_transition.last_patch_summary.ripple_spawned,
            "No-op edit must not play rewrite feedback"
        )

        var old_snow_count := coordinator.current_resolved.find_distribution("snow_rocks").instances.size()
        var stable_rock := main.get_node(
            "WorldRoot/GeneratedWorld/Distributions/snow_rocks/snow_rocks_000"
        ) as Node3D
        var stable_rock_id := stable_rock.get_instance_id()
        coordinator.submit_prompt("雪林里的石头少一点")
        await _wait_until_idle(coordinator)
        var fewer_snow_count := coordinator.current_resolved.find_distribution("snow_rocks").instances.size()
        _expect(fewer_snow_count < old_snow_count, "Snow-rock edit must reduce population")
        _expect(
            (main.get_node("WorldRoot/GeneratedWorld/Distributions/snow_rocks/snow_rocks_000") as Node3D).get_instance_id() == stable_rock_id,
            "Snow-rock edit must preserve retained instance Node identity"
        )

        var old_coastal_count := coordinator.current_resolved.find_distribution("coastal_trees").instances.size()
        var retained_tree := main.get_node(
            "WorldRoot/GeneratedWorld/Distributions/coastal_trees/coastal_trees_000"
        ) as Node3D
        var retained_tree_id := retained_tree.get_instance_id()
        coordinator.submit_prompt("海岸森林的树多一点")
        await _wait_until_idle(coordinator)
        var more_coastal_count := coordinator.current_resolved.find_distribution("coastal_trees").instances.size()
        _expect(more_coastal_count > old_coastal_count, "Coastal-tree edit must increase population")
        _expect(
            (main.get_node("WorldRoot/GeneratedWorld/Distributions/coastal_trees/coastal_trees_000") as Node3D).get_instance_id() == retained_tree_id,
            "Coastal-tree edit must preserve existing instance Node identity"
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

func _wait_until_idle(coordinator: WorldCoordinator) -> void:
    for _frame in range(240):
        if not coordinator.busy:
            return
        await process_frame
    _expect(false, "WorldCoordinator edit did not finish")
