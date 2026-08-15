extends SceneTree

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var fixture: Dictionary = JSON.parse_string(
        FileAccess.get_file_as_string("res://data/fixtures/oweng_semantic_baseline.json")
    )
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var world := WorldBackend.new().lower(fixture.world_ir, catalog, 2026)
    assert(world.errors.is_empty(), " | ".join(world.errors))
    assert(world.regions.size() == 3)
    assert(world.networks.size() == 1)
    assert(world.find_network("main_path") != null)
    assert(world.decorations.is_empty())

    var centers := {}
    for region: ResolvedRegion in world.regions:
        centers[region.semantic_type] = _polygon_center(region.polygon)
    assert(world.terrain.sample_region_weights(centers.coastal_forest).r > 0.55)
    assert(world.terrain.sample_region_weights(centers.research_base).g > 0.55)
    assert(world.terrain.sample_region_weights(centers.snow_forest).b > 0.55)

    var blended_vertices := 0
    var boundary_steps := 0
    var maximum_boundary_height_step := 0.0
    var grid: int = world.terrain.grid_size
    for z in range(grid):
        for x in range(grid):
            var index := z * grid + x
            var mask: Color = world.terrain.surface_masks[index]
            assert(absf(mask.r + mask.g + mask.b - 1.0) < 0.002)
            var active_channels := int(mask.r > 0.12) + int(mask.g > 0.12) + int(mask.b > 0.12)
            if active_channels >= 2:
                blended_vertices += 1
            if x + 1 < grid:
                var next_index := index + 1
                var next_mask: Color = world.terrain.surface_masks[next_index]
                if (
                    mask.a < 0.05
                    and next_mask.a < 0.05
                    and _dominant_channel(mask) != _dominant_channel(next_mask)
                ):
                    boundary_steps += 1
                    var height_step: float = absf(world.terrain.heights[index] - world.terrain.heights[next_index])
                    if height_step > maximum_boundary_height_step:
                        maximum_boundary_height_step = height_step
    assert(blended_vertices > 100)
    assert(boundary_steps > 0)

    var coastal_roughness := _average_local_roughness(world.terrain, 0)
    var research_roughness := _average_local_roughness(world.terrain, 1)
    var snow_roughness := _average_local_roughness(world.terrain, 2)
    assert(maximum_boundary_height_step < 0.65)
    assert(research_roughness < coastal_roughness)
    assert(snow_roughness > coastal_roughness)

    var runtime := SceneRuntime.new()
    var candidate := runtime.build_candidate(world, catalog)
    var terrain_mesh := candidate.get_node("Terrain/WorldSurface/TerrainMesh") as MeshInstance3D
    var terrain_arrays: Array = terrain_mesh.mesh.surface_get_arrays(0)
    var terrain_tangents: PackedFloat32Array = terrain_arrays[Mesh.ARRAY_TANGENT]
    assert(terrain_tangents.size() == grid * grid * 4)
    var terrain_material := terrain_mesh.material_override as ShaderMaterial
    assert(terrain_material != null)
    for ground_type in ["grass", "dirt", "white_sand", "gray_gravel"]:
        var uniform_prefix: String = "sand" if ground_type == "white_sand" else ground_type
        for channel in ["albedo", "normal", "roughness"]:
            var texture := terrain_material.get_shader_parameter(
                "%s_%s" % [uniform_prefix, channel]
            ) as Texture2D
            assert(texture != null, "%s.%s texture was not bound" % [ground_type, channel])
            assert(texture.get_width() == 1024 and texture.get_height() == 1024)
    var pbr_paths: Dictionary = terrain_material.get_meta("oweng_pbr_ground_paths", {})
    assert(pbr_paths.keys().size() == 4)
    for ground_type in ["grass", "dirt", "white_sand", "gray_gravel"]:
        assert(pbr_paths.has(ground_type))
        for path: String in (pbr_paths[ground_type] as Dictionary).values():
            assert(path.begins_with("res://assets/oweng/terrain/"))
            assert(FileAccess.file_exists(path), "Missing OwenG ground texture: %s" % path)
    var path_mesh := candidate.get_node("Networks/main_path/RoadMesh") as MeshInstance3D
    var path_arrays: Array = path_mesh.mesh.surface_get_arrays(0)
    var path_colors: PackedColorArray = path_arrays[Mesh.ARRAY_COLOR]
    assert(path_colors.size() > 20)
    assert(_color_span(path_colors) > 0.25)
    candidate.free()
    runtime.free()

    await _test_environment_and_snow(world, catalog, centers)
    print(
        "Continuous visuals: blend_vertices=%d boundary_height_step=%.3f roughness=%.3f/%.3f/%.3f"
        % [blended_vertices, maximum_boundary_height_step, coastal_roughness, research_roughness, snow_roughness]
    )
    print("Continuous Region visual realization tests passed")
    quit(0)

func _test_environment_and_snow(
    world: ResolvedWorld,
    catalog: PrototypeCatalog,
    centers: Dictionary
) -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    var main := packed.instantiate() as Node3D
    var coordinator := main.get_node("WorldCoordinator") as WorldCoordinator
    coordinator.auto_generate_demo = false
    coordinator.use_http_compiler = false
    main.get_node("UI").free()
    root.add_child(main)
    await process_frame

    var runtime := main.get_node("SceneRuntime") as SceneRuntime
    runtime.commit_candidate(
        main.get_node("WorldRoot"),
        runtime.build_candidate(world, catalog)
    )
    var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
    var snowfall := runtime.get_node("Snowfall") as GPUParticles3D

    var coastal: Vector2 = centers.coastal_forest
    var research: Vector2 = centers.research_base
    var snow: Vector2 = centers.snow_forest
    runtime.update_visual_environment(Vector3(coastal.x, 4.0, coastal.y), 10.0)
    var coastal_fog := environment.fog_density
    assert(snowfall.amount_ratio < 0.05)

    runtime.update_visual_environment(Vector3(research.x, 4.0, research.y), 10.0)
    var research_fog := environment.fog_density
    assert(research_fog > coastal_fog)

    runtime.update_visual_environment(Vector3(snow.x, 4.0, snow.y), 0.10)
    var entering_intensity := snowfall.amount_ratio
    assert(entering_intensity > 0.01 and entering_intensity < 0.95)
    runtime.update_visual_environment(Vector3(snow.x, 4.0, snow.y), 10.0)
    assert(snowfall.amount_ratio > 0.70)
    assert(environment.fog_density > research_fog)
    assert(snowfall.emitting and snowfall.visible)

    runtime.update_visual_environment(Vector3(coastal.x, 4.0, coastal.y), 0.10)
    var leaving_intensity := snowfall.amount_ratio
    assert(leaving_intensity > 0.01 and leaving_intensity < 0.99)
    runtime.update_visual_environment(Vector3(coastal.x, 4.0, coastal.y), 10.0)
    assert(snowfall.amount_ratio < 0.05)
    assert(not snowfall.emitting)
    main.free()

func _average_local_roughness(terrain: ResolvedTerrain, channel: int) -> float:
    var total := 0.0
    var samples := 0
    for z in range(terrain.grid_size - 1):
        for x in range(terrain.grid_size - 1):
            var index := z * terrain.grid_size + x
            var mask: Color = terrain.surface_masks[index]
            var weight := mask.r if channel == 0 else (mask.g if channel == 1 else mask.b)
            if weight < 0.90 or mask.a > 0.05:
                continue
            total += absf(terrain.heights[index] - terrain.heights[index + 1])
            total += absf(terrain.heights[index] - terrain.heights[index + terrain.grid_size])
            samples += 2
    assert(samples > 10)
    return total / float(samples)

func _dominant_channel(color: Color) -> int:
    if color.r >= color.g and color.r >= color.b:
        return 0
    return 1 if color.g >= color.b else 2

func _color_span(colors: PackedColorArray) -> float:
    var minimum := Vector3(INF, INF, INF)
    var maximum := Vector3(-INF, -INF, -INF)
    for color: Color in colors:
        var value := Vector3(color.r, color.g, color.b)
        minimum = minimum.min(value)
        maximum = maximum.max(value)
    return (maximum - minimum).length()

func _polygon_center(polygon: PackedVector2Array) -> Vector2:
    var center := Vector2.ZERO
    for point in polygon:
        center += point
    return center / float(polygon.size())
