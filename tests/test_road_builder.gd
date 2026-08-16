extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var fixture := _load_json("res://data/fixtures/oweng_semantic_baseline.json")
    var world := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    assert(world.errors.is_empty(), " | ".join(world.errors))
    var path: ResolvedNetwork = world.find_network("main_path")
    assert(path != null)
    assert(path.semantic_type == "path")
    assert(path.surface_kind == "path")
    assert(path.width >= 5.0, "Path realization regressed to an unreadably narrow ribbon")
    assert(path.curve_points.size() >= 20, "World-scale paths need a smooth sampled centerline")

    var candidate := SceneRuntime.new().build_candidate(world, catalog)
    var path_node := candidate.get_node_or_null("Networks/main_path")
    assert(path_node != null)
    assert(not path_node.find_children("*", "MeshInstance3D", true, false).is_empty())
    assert(not path_node.find_children("*", "CollisionShape3D", true, false).is_empty())
    var road_mesh := path_node.get_node("RoadMesh") as MeshInstance3D
    var arrays: Array = road_mesh.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    var visual_profiles: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
    assert(vertices.size() > path.curve_points.size() * 6)
    assert(uvs.size() == vertices.size())
    assert(not visual_profiles.is_empty(), "Road shader needs per-vertex Region profile weights")
    candidate.free()
    print("Path builder tests passed")
    quit(0)

func _load_json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
