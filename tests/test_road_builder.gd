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
    assert(path.width > 0.0)
    assert(path.curve_points.size() >= 2)

    var candidate := SceneRuntime.new().build_candidate(world, catalog)
    var path_node := candidate.get_node_or_null("Networks/main_path")
    assert(path_node != null)
    assert(not path_node.find_children("*", "MeshInstance3D", true, false).is_empty())
    assert(not path_node.find_children("*", "CollisionShape3D", true, false).is_empty())
    candidate.free()
    print("Path builder tests passed")
    quit(0)

func _load_json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
