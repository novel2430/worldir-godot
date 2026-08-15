extends SceneTree

const TerrainResolverScript = preload("res://scripts/backend/terrain_resolver.gd")

var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var fixture := _load_json("res://data/fixtures/coastal_town_initial.json")
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var first := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    var repeated := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    var different_seed := WorldBackend.new().lower(fixture.world_ir, catalog, 2026)
    _expect(first.errors.is_empty(), "Terrain fixture must lower")
    _expect(first.terrain != null, "Backend must resolve one terrain surface")
    if first.terrain != null:
        _test_grid_and_determinism(first, repeated, different_seed)
        _test_surface_masks(first)
        _test_local_grading(first, catalog)
        _test_world_conformance(first)
        _test_runtime_surface(first, catalog)
        _test_settlement_flattening(catalog)
    catalog.free()
    if failures == 0:
        print("Terrain and world-surface tests passed")
    quit(1 if failures > 0 else 0)

func _test_grid_and_determinism(first: ResolvedWorld, repeated: ResolvedWorld, different_seed: ResolvedWorld) -> void:
    var terrain: Resource = first.terrain
    _expect(terrain.grid_size == TerrainResolverScript.GRID_SIZE, "Terrain must use the bounded V0 grid resolution")
    _expect(terrain.heights.size() == terrain.grid_size * terrain.grid_size, "Every terrain vertex needs a height")
    _expect(terrain.surface_masks.size() == terrain.heights.size(), "Every terrain vertex needs a surface mask")
    var minimum := INF
    var maximum := -INF
    var differs_from_other_seed := false
    for index in range(terrain.heights.size()):
        var height: float = terrain.heights[index]
        minimum = minf(minimum, height)
        maximum = maxf(maximum, height)
        _expect(is_equal_approx(height, repeated.terrain.heights[index]), "Same seed terrain heights must be deterministic")
        _expect(terrain.surface_masks[index].is_equal_approx(repeated.terrain.surface_masks[index]), "Same seed surface masks must be deterministic")
        differs_from_other_seed = differs_from_other_seed or not is_equal_approx(height, different_seed.terrain.heights[index])
    _expect(maximum - minimum > 1.5, "Macro terrain must be visibly non-flat")
    _expect(minimum >= -2.801 and maximum <= 2.801, "V0 terrain relief must remain restrained")
    _expect(differs_from_other_seed, "Terrain macro shape must be seed-aware")

func _test_surface_masks(world: ResolvedWorld) -> void:
    var has_forest_core := false
    var has_forest_transition := false
    var has_coast_core := false
    var has_road_or_building := false
    for mask: Color in world.terrain.surface_masks:
        has_forest_core = has_forest_core or mask.r > 0.9
        has_forest_transition = has_forest_transition or (mask.r > 0.05 and mask.r < 0.9)
        has_coast_core = has_coast_core or mask.b > 0.9
        has_road_or_building = has_road_or_building or mask.a > 0.9
    _expect(has_forest_core, "Forest floor influence must cover the resolved forest interior")
    _expect(has_forest_transition, "Forest influence must feather across its mathematical edge")
    _expect(has_coast_core, "Coast influence must produce sand surface")
    _expect(has_road_or_building, "Roads/buildings must contribute local dirt influence")

    var road: ResolvedNetwork = world.find_network("main_road")
    var road_point := Vector2(road.curve_points[road.curve_points.size() / 2].x, road.curve_points[road.curve_points.size() / 2].z)
    _expect(world.terrain.sample_surface_mask(road_point).a > 0.9, "Road core must be fully dirt-influenced")
    var church: ResolvedEntity = world.find_entity("church")
    var church_point := Vector2(church.transform.origin.x, church.transform.origin.z)
    _expect(world.terrain.sample_surface_mask(church_point).a > 0.85, "A landmark footprint must affect its local ground")

func _test_world_conformance(world: ResolvedWorld) -> void:
    for network: ResolvedNetwork in world.networks:
        for point in network.curve_points:
            var expected: float = world.terrain.sample_height(Vector2(point.x, point.z)) + TerrainResolverScript.ROAD_SURFACE_OFFSET
            _expect(is_equal_approx(point.y, expected), "Road geometry must conform to terrain")
    for entity: ResolvedEntity in world.entities:
        var expected: float = world.terrain.sample_height(Vector2(entity.transform.origin.x, entity.transform.origin.z)) + TerrainResolverScript.INSTANCE_SURFACE_OFFSET
        _expect(is_equal_approx(entity.transform.origin.y, expected), "Entity roots must conform to terrain")
    for distribution: ResolvedDistribution in world.distributions:
        for item in distribution.instances:
            var transform: Transform3D = item["transform"]
            var expected: float = world.terrain.sample_height(Vector2(transform.origin.x, transform.origin.z)) + TerrainResolverScript.INSTANCE_SURFACE_OFFSET
            _expect(is_equal_approx(transform.origin.y, expected), "Semantic populations must conform to terrain")
    for decoration: ResolvedDecoration in world.decorations:
        for item in decoration.instances:
            var transform: Transform3D = item["transform"]
            var expected: float = world.terrain.sample_height(Vector2(transform.origin.x, transform.origin.z)) + TerrainResolverScript.INSTANCE_SURFACE_OFFSET
            _expect(is_equal_approx(transform.origin.y, expected), "Forest dressing must conform to resolved terrain")

func _test_local_grading(world: ResolvedWorld, catalog: PrototypeCatalog) -> void:
    var road: ResolvedNetwork = world.find_network("main_road")
    var segment_index := (road.curve_points.size() - 1) / 2
    var a := Vector2(road.curve_points[segment_index].x, road.curve_points[segment_index].z)
    var b := Vector2(road.curve_points[segment_index + 1].x, road.curve_points[segment_index + 1].z)
    var center := a.lerp(b, 0.5)
    var tangent := (b - a).normalized()
    var normal := Vector2(-tangent.y, tangent.x)
    var core_offset := road.width * 0.36
    var center_height: float = world.terrain.sample_height(center)
    var left_height: float = world.terrain.sample_height(center + normal * core_offset)
    var right_height: float = world.terrain.sample_height(center - normal * core_offset)
    _expect(absf(left_height - center_height) < 0.06, "Road terrain core must be graded flat across its left half")
    _expect(absf(right_height - center_height) < 0.06, "Road terrain core must be graded flat across its right half")

    var church: ResolvedEntity = world.find_entity("church")
    var church_meta := catalog.get_metadata(church.prototype_id)
    var footprint: Vector2 = church_meta.get("visual_footprint", Vector2.ONE * 4.0)
    var pad_sample_radius := minf(footprint.x, footprint.y) * 0.3
    var church_center := Vector2(church.transform.origin.x, church.transform.origin.z)
    var pad_height: float = world.terrain.sample_height(church_center)
    for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
        var sample_height: float = world.terrain.sample_height(church_center + direction * pad_sample_radius)
        _expect(absf(sample_height - pad_height) < 0.06, "Building footprint must sit on a locally level terrain pad")

func _test_runtime_surface(world: ResolvedWorld, catalog: PrototypeCatalog) -> void:
    var runtime := SceneRuntime.new()
    var candidate := runtime.build_candidate(world, catalog)
    _expect(candidate != null, "Runtime must instantiate the terrain-backed world")
    if candidate == null:
        runtime.free()
        return
    var body := candidate.get_node_or_null("Terrain/WorldSurface") as StaticBody3D
    _expect(body != null, "Runtime must create one world surface body")
    var mesh_instance := body.get_node_or_null("TerrainMesh") as MeshInstance3D
    var collision := body.get_node_or_null("TerrainCollision") as CollisionShape3D
    _expect(mesh_instance != null and mesh_instance.mesh != null, "World surface must have procedural geometry")
    _expect(mesh_instance.material_override is ShaderMaterial, "World surface must use the stylized mask shader")
    _expect(collision != null and collision.shape is ConcavePolygonShape3D, "World surface must expose matching terrain collision")
    var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
    var expected_vertices: int = world.terrain.grid_size * world.terrain.grid_size
    var expected_indices: int = (world.terrain.grid_size - 1) * (world.terrain.grid_size - 1) * 6
    _expect((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == expected_vertices, "Terrain mesh must match its resolved grid")
    _expect((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == expected_indices, "Terrain mesh must triangulate every grid cell")
    for region: ResolvedRegion in world.regions:
        _expect(candidate.get_node("Regions/%s" % region.id).get_child_count() == 0, "Resolved Regions must not add stacked surface polygons")
    candidate.free()
    runtime.free()

func _test_settlement_flattening(catalog: PrototypeCatalog) -> void:
    var empty_ir := {"regions": [], "networks": [], "entities": [], "distributions": []}
    var village_ir := {
        "regions": [{"id": "village", "type": "village", "placement": {"anchor": "center"}}],
        "networks": [], "entities": [], "distributions": [],
    }
    var natural := WorldBackend.new().lower(empty_ir, catalog, 404)
    var village := WorldBackend.new().lower(village_ir, catalog, 404)
    _expect(natural.errors.is_empty() and village.errors.is_empty(), "Settlement terrain comparison must lower")
    var natural_samples := PackedFloat32Array()
    var village_samples := PackedFloat32Array()
    for index in range(village.terrain.surface_masks.size()):
        if village.terrain.surface_masks[index].g > 0.9:
            natural_samples.append(natural.terrain.heights[index])
            village_samples.append(village.terrain.heights[index])
    _expect(village_samples.size() > 20, "Village mask must expose a stable interior sample")
    _expect(_standard_deviation(village_samples) < _standard_deviation(natural_samples) * 0.45, "Village influence must substantially calm local terrain")

func _standard_deviation(values: PackedFloat32Array) -> float:
    if values.is_empty():
        return 0.0
    var mean := 0.0
    for value in values:
        mean += value
    mean /= float(values.size())
    var variance := 0.0
    for value in values:
        variance += (value - mean) * (value - mean)
    return sqrt(variance / float(values.size()))

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
