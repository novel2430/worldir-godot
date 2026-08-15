extends SceneTree

const DEMO_SCENE := "res://scenes/chunk_streaming_demo.tscn"
const OUTPUT_DIR := "res://screenshots/artlab_policy"

var _demo: Node3D
var _camera: Camera3D

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(DEMO_SCENE) as PackedScene
    if packed == null:
        push_error("Could not load %s" % DEMO_SCENE)
        quit(1)
        return

    _demo = packed.instantiate() as Node3D
    root.add_child(_demo)
    await process_frame

    var manager := _demo.get_node_or_null("ChunkManager") as ChunkManager
    if manager == null or not manager.initialized:
        push_error("Chunk streaming demo did not initialize")
        quit(1)
        return
    if manager.get_active_records().size() != 9:
        push_error("Expected a 3x3 active Chunk window")
        quit(1)
        return

    var player_camera := _demo.get_node_or_null("Player/CameraPivot/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var player := _demo.get_node_or_null("Player") as Node3D
    if player != null:
        player.process_mode = Node.PROCESS_MODE_DISABLED
    var debug_ui := _demo.get_node_or_null("DebugUI") as CanvasLayer
    if debug_ui != null:
        debug_ui.visible = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

    _camera = Camera3D.new()
    _camera.name = "EvidenceCamera"
    _camera.current = true
    _camera.near = 0.1
    _camera.far = 1800.0
    _demo.add_child(_camera)

    var absolute_output := ProjectSettings.globalize_path(OUTPUT_DIR)
    var directory_error := DirAccess.make_dir_recursive_absolute(absolute_output)
    if directory_error != OK:
        push_error("Could not create capture directory: %s" % absolute_output)
        quit(1)
        return

    var views := [
        {
            "file": "01_active_window_overview.png",
            "position": Vector3(365.0, 330.0, 365.0),
            "target": Vector3(80.0, 0.0, 80.0),
            "fov": 52.0,
        },
        {
            "file": "02_central_chunk_overview.png",
            "position": Vector3(210.0, 150.0, 220.0),
            "target": Vector3(72.0, 0.0, 74.0),
            "fov": 48.0,
        },
        {
            "file": "03_forest_edge_dressing.png",
            "position": Vector3(50.0, 22.0, 142.0),
            "target": Vector3(18.0, 2.5, 76.0),
            "fov": 58.0,
        },
        {
            "file": "04_road_building_clearings.png",
            "position": Vector3(128.0, 22.0, 152.0),
            "target": Vector3(80.0, 2.0, 74.0),
            "fov": 56.0,
        },
        {
            "file": "05_coast_surface_transition.png",
            "position": Vector3(90.0, 18.0, 36.0),
            "target": Vector3(151.0, 0.0, 84.0),
            "fov": 60.0,
        },
        {
            "file": "06_chunk_boundary_continuity.png",
            "position": Vector3(160.0, 40.0, 232.0),
            "target": Vector3(160.0, 0.0, 145.0),
            "fov": 50.0,
        },
    ]

    for view: Dictionary in views:
        var camera_position: Vector3 = view["position"]
        var target: Vector3 = view["target"]
        var ok := await _capture_view(
            String(view["file"]),
            camera_position,
            target,
            float(view["fov"])
        )
        if not ok:
            quit(1)
            return

    _print_world_metrics(manager)
    print("Captured %d ArtLab-policy views to %s" % [views.size(), absolute_output])
    quit(0)

func _capture_view(
    file_name: String,
    camera_position: Vector3,
    target: Vector3,
    field_of_view: float
) -> bool:
    _camera.global_position = camera_position
    _camera.fov = field_of_view
    _camera.look_at(target, Vector3.UP)
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("Viewport image is empty for %s" % file_name)
        return false
    var output_path := "%s/%s" % [OUTPUT_DIR, file_name]
    var error := image.save_png(ProjectSettings.globalize_path(output_path))
    if error != OK:
        push_error("Could not save %s: error %d" % [output_path, error])
        return false
    print("CAPTURED %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
    return true

func _print_world_metrics(manager: ChunkManager) -> void:
    var decoration_count := 0
    var distribution_count := 0
    var entity_count := 0
    for record: ChunkRecord in manager.get_active_records():
        var resolved := record.resolved_chunk
        if resolved == null:
            continue
        entity_count += resolved.entities.size()
        for distribution: ResolvedDistribution in resolved.distributions:
            distribution_count += distribution.instances.size()
        for decoration: ResolvedDecoration in resolved.decorations:
            decoration_count += decoration.instances.size()
    print(
        "WORLD_METRICS active_chunks=%d entities=%d distributions=%d decorations=%d"
        % [manager.get_active_records().size(), entity_count, distribution_count, decoration_count]
    )
