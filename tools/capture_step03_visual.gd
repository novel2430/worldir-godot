extends SceneTree

const OUTPUT_DIR := "res://screenshots/step03"

var main: Node3D
var coordinator: WorldCoordinator
var runtime: SceneRuntime
var player: Node3D
var camera: Camera3D

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    root.size = Vector2i(1280, 720)
    main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
    coordinator = main.get_node("WorldCoordinator") as WorldCoordinator
    coordinator.use_http_compiler = false
    coordinator.auto_generate_demo = true
    main.get_node("UI").free()
    # The capture runner positions the camera directly and must not capture the
    # desktop mouse when its off-screen/automation window enters the tree.
    main.get_node("Player").set_script(null)
    root.add_child(main)
    await _wait_until_idle()
    assert(coordinator.current_resolved != null)
    runtime = main.get_node("SceneRuntime") as SceneRuntime
    player = main.get_node("Player") as Node3D
    camera = player.get_node("CameraPivot/Camera3D") as Camera3D
    var initial_snow_rocks := coordinator.current_resolved.find_distribution("snow_rocks").instances.size()
    var initial_coastal_trees := coordinator.current_resolved.find_distribution("coastal_trees").instances.size()

    var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
    DirAccess.make_dir_recursive_absolute(output_path)
    var centers := _region_centers(coordinator.current_resolved)
    await _capture_overview("01_world_overview.png", centers.research_base)
    await _capture_region("02_coastal_before_more_trees.png", centers.coastal_forest, Vector3(25.0, 17.0, 23.0))
    await _capture_region("03_research_base.png", centers.research_base, Vector3(29.0, 22.0, 28.0))
    await _capture_region("04_snow_before_fewer_rocks.png", centers.snow_forest, Vector3(27.0, 18.0, 24.0))

    coordinator.submit_prompt("雪林里的石头少一点")
    await _wait_until_idle()
    var snow_edit_timings := coordinator.last_update_timings_ms.duplicate(true)
    await _capture_region("05_snow_after_fewer_rocks.png", centers.snow_forest, Vector3(27.0, 18.0, 24.0))
    coordinator.submit_prompt("海岸森林的树多一点")
    await _wait_until_idle()
    var tree_edit_timings := coordinator.last_update_timings_ms.duplicate(true)
    await _capture_region("06_coastal_after_more_trees.png", centers.coastal_forest, Vector3(25.0, 17.0, 23.0))

    print(
        "Captured Step 03 visuals: snow_rocks=%d->%d coastal_trees=%d->%d"
        % [
            initial_snow_rocks,
            coordinator.current_resolved.find_distribution("snow_rocks").instances.size(),
            initial_coastal_trees,
            coordinator.current_resolved.find_distribution("coastal_trees").instances.size(),
        ]
    )
    print("Snow edit timings ms: ", snow_edit_timings)
    print("Tree edit timings ms: ", tree_edit_timings)
    main.free()
    quit(0)

func _wait_until_idle() -> void:
    for _frame in range(900):
        if not coordinator.busy and coordinator.current_resolved != null:
            await process_frame
            return
        await process_frame
    assert(false, "Timed out waiting for WorldCoordinator")

func _capture_overview(file_name: String, environment_position: Vector2) -> void:
    var terrain := coordinator.current_resolved.terrain
    player.position = Vector3(
        environment_position.x,
        terrain.sample_height(environment_position) + 2.0,
        environment_position.y
    )
    runtime.update_visual_environment(player.global_position, 10.0)
    camera.global_position = Vector3(0.0, 72.0, 92.0)
    camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
    await _save_frame(file_name)

func _capture_region(file_name: String, center: Vector2, offset: Vector3) -> void:
    var terrain := coordinator.current_resolved.terrain
    var height: float = terrain.sample_height(center)
    player.position = Vector3(center.x, height + 2.0, center.y)
    runtime.update_visual_environment(player.global_position, 10.0)
    camera.global_position = Vector3(center.x + offset.x, height + offset.y, center.y + offset.z)
    camera.look_at(Vector3(center.x, height + 1.5, center.y), Vector3.UP)
    await _save_frame(file_name)

func _save_frame(file_name: String) -> void:
    for _frame in range(5):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    assert(image != null and not image.is_empty())
    var error := image.save_png(ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name]))
    assert(error == OK, error_string(error))
    print("Captured ", file_name)

func _region_centers(world: ResolvedWorld) -> Dictionary:
    var result := {}
    for region: ResolvedRegion in world.regions:
        var center := Vector2.ZERO
        for point in region.polygon:
            center += point
        result[region.semantic_type] = center / float(region.polygon.size())
    return result
