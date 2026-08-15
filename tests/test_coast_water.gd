extends SceneTree

const CoastResolverScript = preload("res://scripts/backend/coast_resolver.gd")

var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var fixture := _load_json("res://data/fixtures/coastal_town_initial.json")
    var ir_before := JSON.stringify(fixture.world_ir)
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var first := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    var repeated := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    var different_seed := WorldBackend.new().lower(fixture.world_ir, catalog, 7331)
    _expect(first.errors.is_empty(), "Coastal fixture must lower")
    _expect(JSON.stringify(fixture.world_ir) == ir_before, "Ocean realization must not mutate World IR")
    _test_resolved_ocean(first, repeated, different_seed)
    _test_coast_profile(first)
    _test_runtime(first, catalog)
    _test_boundary_directions()
    _test_inland_coast_skips_ocean(catalog)
    _test_no_coast(catalog)
    catalog.free()
    if failures == 0:
        print("Coast and stylized water tests passed")
    quit(1 if failures > 0 else 0)

func _test_resolved_ocean(first: ResolvedWorld, repeated: ResolvedWorld, different_seed: ResolvedWorld) -> void:
    _expect(first.waters.size() == 1, "One boundary Coast must produce one backend ocean")
    _expect(repeated.waters.size() == 1 and different_seed.waters.size() == 1, "Repeated coastal worlds must resolve water")
    if first.waters.is_empty():
        return
    var water: Resource = first.waters[0]
    var repeated_water: Resource = repeated.waters[0]
    var other_water: Resource = different_seed.waters[0]
    _expect(water.id == "__backend_ocean__coast", "Backend ocean id must be stable and namespaced")
    _expect(water.source_region_id == "coast", "Resolved water must retain its source Region identity")
    _expect(water.seaward_direction.is_equal_approx(Vector2.RIGHT), "East Coast must infer eastward ocean without rereading IR anchor")
    _expect(is_equal_approx(water.sea_level, CoastResolverScript.SEA_LEVEL), "Ocean must use the backend sea-level policy")
    _expect(water.shoreline.size() == CoastResolverScript.SHORE_SAMPLES, "Shoreline must use bounded deterministic sampling")
    _expect(water.polygon.size() == water.shoreline.size() + 2, "Water polygon must close shoreline against the world edge")
    var seed_changes_shape := false
    for index in range(water.shoreline.size()):
        _expect(water.shoreline[index].is_equal_approx(repeated_water.shoreline[index]), "Same seed shoreline must be deterministic")
        seed_changes_shape = seed_changes_shape or not water.shoreline[index].is_equal_approx(other_water.shoreline[index])
    _expect(seed_changes_shape, "Different seed must alter shoreline realization")
    _expect(is_equal_approx(water.polygon[water.polygon.size() - 1].x, first.world_bounds.end.x), "Ocean polygon must terminate at inferred world edge")

func _test_coast_profile(world: ResolvedWorld) -> void:
    var water: Resource = world.waters[0]
    var shore: Vector2 = water.shoreline[water.shoreline.size() / 2]
    var land_point: Vector2 = shore - water.seaward_direction * 8.0
    var wet_point: Vector2 = shore - water.seaward_direction * 0.6
    var sea_point: Vector2 = shore + water.seaward_direction * 8.0
    var land_height: float = world.terrain.sample_height(land_point)
    var shore_height: float = world.terrain.sample_height(shore)
    var sea_floor_height: float = world.terrain.sample_height(sea_point)
    _expect(land_height > water.sea_level + 0.12, "Dry beach must remain visibly above sea level")
    _expect(shore_height < water.sea_level, "Terrain must dip just below water at the shoreline")
    _expect(sea_floor_height < shore_height - 0.15, "Submerged terrain must descend away from shore")
    _expect(world.terrain.sample_surface_mask(land_point).b > 0.45, "Landward coast transition must become sand")
    _expect(world.terrain.sample_shore_wetness(wet_point) > 0.45, "A narrow wet-sand band must exist landward of water")

func _test_runtime(world: ResolvedWorld, catalog: PrototypeCatalog) -> void:
    var runtime := SceneRuntime.new()
    var candidate := runtime.build_candidate(world, catalog)
    _expect(candidate != null, "Runtime must instantiate ResolvedWater")
    if candidate == null:
        runtime.free()
        return
    var water_root := candidate.get_node_or_null("Water/__backend_ocean__coast") as Node3D
    _expect(water_root != null, "Ocean must live in a dedicated runtime Water layer")
    if water_root != null:
        var water_mesh := water_root.get_node("WaterMesh") as MeshInstance3D
        var foam := water_root.get_node("ShoreFoam") as MeshInstance3D
        _expect(water_mesh.mesh.get_faces().size() > 1000, "Water surface must be subdivided enough for restrained vertex waves")
        _expect(water_mesh.material_override is ShaderMaterial, "Water must use the stylized water shader")
        var water_shader_code := (water_mesh.material_override as ShaderMaterial).shader.code
        _expect("moving_ripple" in water_shader_code and "TIME" in water_shader_code, "Water color variation must visibly animate")
        _expect("NORMAL =" in water_shader_code and "fresnel" in water_shader_code, "Water must vary lighting through wave normals and view angle")
        _expect(foam.material_override is ShaderMaterial and not foam.mesh.get_faces().is_empty(), "Shoreline must include a procedural foam strip")
        _expect(water_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Water must not cast a solid plane shadow")
    candidate.free()
    runtime.free()

func _test_boundary_directions() -> void:
    var bounds := Rect2(-80.0, -80.0, 160.0, 160.0)
    var cases := [
        {"direction": Vector2.LEFT, "rect": Rect2(-80.0, -40.0, 35.0, 80.0)},
        {"direction": Vector2.RIGHT, "rect": Rect2(45.0, -40.0, 35.0, 80.0)},
        {"direction": Vector2.UP, "rect": Rect2(-40.0, -80.0, 80.0, 35.0)},
        {"direction": Vector2.DOWN, "rect": Rect2(-40.0, 45.0, 80.0, 35.0)},
    ]
    for case in cases:
        var world := ResolvedWorld.new()
        world.world_bounds = bounds
        world.seed = 99
        var coast := ResolvedRegion.new()
        coast.id = "coast"
        coast.semantic_type = "coast"
        coast.polygon = _rect_polygon(case["rect"])
        world.regions.append(coast)
        var waters := CoastResolverScript.new().resolve(world)
        _expect(waters.size() == 1, "Every cardinal boundary Coast must resolve an ocean")
        if not waters.is_empty():
            _expect(waters[0].seaward_direction.is_equal_approx(case["direction"]), "Ocean direction must follow the contacted boundary")

func _test_inland_coast_skips_ocean(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [{"id": "inland_coast", "type": "coast"}],
        "networks": [], "entities": [], "distributions": [],
    }
    var binding := [{"ir_object_id": "inland_coast", "runtime_fact_id": "inland", "placement": "inside"}]
    var payloads := {"inland": {"aabb2": {"x": -20.0, "z": -20.0, "w": 40.0, "d": 40.0}}}
    var world := WorldBackend.new().lower(ir, catalog, 55, binding, payloads)
    _expect(world.errors.is_empty(), "Inland coast geometry remains legal")
    _expect(world.waters.is_empty(), "Coast not touching world boundary must not invent an inland ocean")
    _expect(not world.warnings.is_empty(), "Skipped ambiguous inland ocean should produce a backend warning")
    _expect(world.terrain.sample_surface_mask(Vector2.ZERO).b > 0.9, "Inland Coast must retain its sand surface realization")

func _test_no_coast(catalog: PrototypeCatalog) -> void:
    var ir := {"regions": [{"id": "field", "type": "field"}], "networks": [], "entities": [], "distributions": []}
    var world := WorldBackend.new().lower(ir, catalog, 12)
    _expect(world.errors.is_empty() and world.waters.is_empty(), "World without Coast must not generate water")

func _rect_polygon(rect: Rect2) -> PackedVector2Array:
    return PackedVector2Array([
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y),
    ])

func _load_json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
