extends SceneTree

var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var fixture_file := FileAccess.open("res://data/fixtures/coastal_town_initial.json", FileAccess.READ)
    _expect(fixture_file != null, "Coastal town fixture must be readable")
    if fixture_file == null:
        _finish()
        return
    var fixture: Variant = JSON.parse_string(fixture_file.get_as_text())
    _expect(typeof(fixture) == TYPE_DICTIONARY, "Coastal town fixture must contain JSON")
    if typeof(fixture) != TYPE_DICTIONARY:
        _finish()
        return

    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var resolved := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    _expect(resolved.errors.is_empty(), "Fixture must lower before runtime mesh construction")
    var network: ResolvedNetwork = resolved.find_network("main_road")
    _expect(network != null, "Lowered fixture must contain main_road")
    if network == null:
        catalog.free()
        _finish()
        return
    _expect(network.curve_points.size() >= 2, "NetworkLowerer must produce road curve points")
    _expect(is_equal_approx(network.width, 4.2), "Road width must reach RoadBuilder unchanged")

    var scene_runtime := SceneRuntime.new()
    var candidate := scene_runtime.build_candidate(resolved, catalog)
    root.add_child(candidate)

    _expect(candidate.is_inside_tree(), "Candidate world must enter the SceneTree")
    var road := candidate.get_node_or_null("Networks/main_road") as Node3D
    _expect(road != null, "SceneRuntime must attach the built road under Networks")
    if road == null:
        candidate.free()
        scene_runtime.free()
        catalog.free()
        _finish()
        return
    var road_mesh_instance := road.get_node_or_null("RoadMesh") as MeshInstance3D
    _expect(road_mesh_instance != null, "RoadBuilder must attach RoadMesh")
    if road_mesh_instance == null or road_mesh_instance.mesh == null:
        candidate.free()
        scene_runtime.free()
        catalog.free()
        _finish()
        return

    var road_arrays: Array = road_mesh_instance.mesh.surface_get_arrays(0)
    var road_vertices: PackedVector3Array = road_arrays[Mesh.ARRAY_VERTEX]
    var road_normals: PackedVector3Array = road_arrays[Mesh.ARRAY_NORMAL]
    var expected_vertex_count: int = (network.curve_points.size() - 1) * 6
    _expect(road_vertices.size() == expected_vertex_count, "Each road segment must produce two triangles")
    _expect(road_normals.size() == road_vertices.size(), "Every road vertex must have a normal")

    for triangle_start in range(0, road_vertices.size(), 3):
        var geometric_normal := _triangle_normal(
            road_vertices[triangle_start],
            road_vertices[triangle_start + 1],
            road_vertices[triangle_start + 2]
        )
        # Godot front faces use clockwise winding. For an upward-facing XZ
        # surface, the raw cross product therefore points toward -Y.
        _expect(geometric_normal.dot(Vector3.DOWN) > 0.999, "Road triangle winding must face upward in Godot")
        _expect(not geometric_normal.is_zero_approx(), "Road triangles must not be degenerate")

    for normal in road_normals:
        _expect(normal.dot(Vector3.UP) > 0.999, "Road lighting normals must point upward")

    var material := road_mesh_instance.material_override as StandardMaterial3D
    _expect(material != null, "Road mesh must have a material")
    if material != null:
        _expect(material.cull_mode == BaseMaterial3D.CULL_BACK, "Road must remain backface-culled")
        _expect(material.albedo_color.is_equal_approx(Color(0.29, 0.245, 0.18)), "Road must use the muted warm dirt palette")
        _expect(is_equal_approx(material.roughness, 1.0), "Road material must stay fully rough")
    _expect(is_equal_approx(road_mesh_instance.mesh.get_aabb().position.y, 0.08), "Road mesh must retain its visible height")
    _test_curved_road_joins()

    candidate.free()
    scene_runtime.free()
    catalog.free()
    _finish()

func _test_curved_road_joins() -> void:
    var network := ResolvedNetwork.new()
    network.id = "curved_road"
    network.width = 6.0
    network.curve_points = PackedVector3Array([
        Vector3(0.0, 0.08, 12.0),
        Vector3(0.0, 0.08, 0.0),
        Vector3(0.0, 0.08, 0.0), # Duplicate must not create a degenerate segment.
        Vector3(12.0, 0.08, 0.0),
        Vector3(13.5, 0.08, 10.0), # Sharp reversal exercises the miter limit.
    ])
    var road := RoadBuilder.new().build(network)
    var mesh_instance := road.get_node_or_null("RoadMesh") as MeshInstance3D
    _expect(mesh_instance != null and mesh_instance.mesh != null, "Curved road must produce a mesh")
    if mesh_instance == null or mesh_instance.mesh == null:
        road.free()
        return

    var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var cleaned_points := PackedVector3Array([
        network.curve_points[0],
        network.curve_points[1],
        network.curve_points[3],
        network.curve_points[4],
    ])
    var segment_count := cleaned_points.size() - 1
    _expect(vertices.size() == segment_count * 6, "Duplicate centerline points must be removed before meshing")

    for join_index in range(segment_count - 1):
        var previous_base := join_index * 6
        var next_base := (join_index + 1) * 6
        var previous_left: Vector3 = vertices[previous_base + 2]
        var previous_right: Vector3 = vertices[previous_base + 1]
        var next_left: Vector3 = vertices[next_base]
        var next_right: Vector3 = vertices[next_base + 4]
        _expect(previous_left.is_equal_approx(next_left), "Adjacent segments must share the same left join vertex")
        _expect(previous_right.is_equal_approx(next_right), "Adjacent segments must share the same right join vertex")

        var center: Vector3 = cleaned_points[join_index + 1]
        var left_offset := Vector2(previous_left.x - center.x, previous_left.z - center.z).length()
        var right_offset := Vector2(previous_right.x - center.x, previous_right.z - center.z).length()
        var maximum_miter := network.width * 0.5 * RoadBuilder.MITER_LIMIT + 0.001
        _expect(left_offset <= maximum_miter, "Left join must respect the miter limit")
        _expect(right_offset <= maximum_miter, "Right join must respect the miter limit")

    for triangle_start in range(0, vertices.size(), 3):
        var geometric_normal := _triangle_normal(
            vertices[triangle_start],
            vertices[triangle_start + 1],
            vertices[triangle_start + 2]
        )
        _expect(not geometric_normal.is_zero_approx(), "Curved road triangles must not be degenerate")
        _expect(geometric_normal.dot(Vector3.DOWN) > 0.999, "Curved road top faces must keep upward Godot winding")

    _expect(road.get_child_count() == segment_count + 1, "Curved road collision must contain one body per cleaned segment")
    road.free()

func _triangle_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    return (b - a).cross(c - a).normalized()

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)

func _finish() -> void:
    if failures == 0:
        print("RoadBuilder runtime mesh tests passed")
    quit(1 if failures > 0 else 0)
