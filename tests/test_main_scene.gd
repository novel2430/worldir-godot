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
    var initial_canvas := main.get_node_or_null("WorldRoot/InitialCanvas") as Node3D
    _expect(initial_canvas != null, "Main scene must start on the flat grass canvas")
    _expect(
        main.get_node_or_null("WorldRoot/GeneratedWorld") == null,
        "Initial canvas must not masquerade as a resolved semantic world"
    )
    if initial_canvas != null:
        var initial_mesh := initial_canvas.get_node("InitialGround/GrassMesh") as MeshInstance3D
        _expect(initial_mesh.mesh is PlaneMesh, "Initial canvas ground must remain completely flat")
        _expect(
            initial_canvas.get_node_or_null("InitialGround/CollisionShape3D") is CollisionShape3D,
            "Initial canvas must give the player a real ground collision"
        )
    var compass := main.get_node("UI/CompassHUD") as Control
    _expect(compass != null, "Main HUD must include the compact heading compass")
    _expect(compass.size.x <= 100.0 and compass.size.y <= 100.0, "Compass HUD must remain compact")
    var prompt_panel := main.get_node("UI/PromptPanel") as PanelContainer
    root.add_child(main)
    await process_frame
    await process_frame
    _expect(bool(prompt_panel.get("debug_mode")), "Prompt UI must default to Debug mode in the Editor")
    _expect(prompt_panel.get_node("Margin/VBox/DebugHeader").visible, "Debug mode must show its header")
    prompt_panel.set("debug_mode", false)
    _expect(not prompt_panel.get_node("Margin/VBox/DebugHeader").visible, "Compact mode must hide debug chrome")
    _expect(not prompt_panel.get_node("Margin/VBox/DebugDetails").visible, "Compact mode must hide technical status")
    coordinator.status_changed.emit("IR GAP: unsupported test relation")
    _expect(prompt_panel.get_node("Margin/VBox/GapPanel").visible, "Compact mode must reveal IR GAP failures")
    coordinator.status_changed.emit("Compiling semantic world...")
    _expect(not prompt_panel.get_node("Margin/VBox/GapPanel").visible, "Compact mode must hide normal status messages")
    prompt_panel.set("debug_mode", true)
    var player := main.get_node("Player") as PlayerController
    var camera := main.get_node("Player/CameraPivot/Camera3D") as Camera3D
    _expect(player.move_speed <= 5.2, "Player movement should use the slower exploration calibration")
    _expect(player.acceleration > 0.0 and player.deceleration > player.acceleration, "Player movement should accelerate and decelerate smoothly")
    _expect(camera.far <= 150.0, "Camera distance should hide the finite world edge")
    _expect(coordinator.current_resolved != null, "Fake compiler must commit the demo world")
    if coordinator.current_resolved != null:
        _expect(coordinator.current_resolved.terrain != null, "Committed demo must include resolved terrain")
        _expect(main.get_node_or_null("WorldRoot/GeneratedWorld/Terrain/WorldSurface") != null, "Committed scene must contain the world surface")
        _expect(main.get_node_or_null("BaseGround") == null, "Legacy flat base ground must stay removed")
        var fading_canvas := main.get_node_or_null("WorldRoot/InitialCanvas") as Node3D
        _expect(
            fading_canvas == null or bool(fading_canvas.get_meta("reveal_out_started", false)),
            "First successful commit must retire the initial canvas through the reveal transition"
        )
        var generated := main.get_node("WorldRoot/GeneratedWorld") as Node3D
        var stable_tree := generated.get_node("Distributions/coastal_trees/coastal_trees_000") as Node3D
        var stable_terrain := generated.get_node("Terrain/WorldSurface") as Node3D
        var stable_road := generated.get_node("Networks/main_path") as Node3D
        var generated_id := generated.get_instance_id()
        var tree_id := stable_tree.get_instance_id()
        var terrain_id := stable_terrain.get_instance_id()
        var road_id := stable_road.get_instance_id()
        var terrain_resource := coordinator.current_resolved.terrain
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
        _expect(bool(coordinator.last_update_timings_ms.terrain_reused), "No-op edit must reuse terrain")

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
        _expect(coordinator.current_resolved.terrain == terrain_resource, "Population reduction must reuse terrain data")
        _expect(int(coordinator.last_update_timings_ms.candidate_prototypes) == 0, "Population reduction must not build unchanged prototypes")

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
        _expect(coordinator.current_resolved.terrain == terrain_resource, "Population growth must reuse terrain data")
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
