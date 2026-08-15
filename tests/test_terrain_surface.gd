extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var ir: Dictionary = _load_json("res://data/fixtures/oweng_semantic_baseline.json").world_ir
    var first := WorldBackend.new().lower(ir, catalog, 8181)
    var repeated := WorldBackend.new().lower(ir, catalog, 8181)
    assert(first.errors.is_empty() and repeated.errors.is_empty())
    assert(first.terrain != null)
    assert(first.terrain.grid_size > 1)
    assert(first.terrain.heights == repeated.terrain.heights)
    assert(first.terrain.surface_masks == repeated.terrain.surface_masks)
    for entity: ResolvedEntity in first.entities:
        var expected: float = first.terrain.sample_height(Vector2(entity.transform.origin.x, entity.transform.origin.z))
        assert(absf(entity.transform.origin.y - expected) < 0.1)
    for distribution: ResolvedDistribution in first.distributions:
        for instance: Dictionary in distribution.instances:
            var transform: Transform3D = instance.transform
            var expected: float = first.terrain.sample_height(Vector2(transform.origin.x, transform.origin.z))
            assert(absf(transform.origin.y - expected) < 0.1)

    var candidate := SceneRuntime.new().build_candidate(first, catalog)
    assert(candidate.get_node_or_null("Terrain/WorldSurface/TerrainMesh") != null)
    assert(candidate.get_node_or_null("Terrain/WorldSurface/TerrainCollision") != null)
    candidate.free()
    print("Resolved terrain surface tests passed")
    quit(0)

func _load_json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
