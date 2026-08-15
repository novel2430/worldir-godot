extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var ir := {
        "regions": [{"id": "coastal", "type": "coastal_forest"}],
        "networks": [], "entities": [], "distributions": [],
    }
    var world := WorldBackend.new().lower(ir, catalog, 911)
    assert(world.errors.is_empty())
    assert(world.waters.is_empty())
    assert(world.entities.is_empty())
    assert(world.distributions.is_empty())
    assert(world.decorations.is_empty())
    var candidate := SceneRuntime.new().build_candidate(world, catalog)
    assert(candidate.get_node("Water").get_child_count() == 0)
    candidate.free()
    print("Coastal profile implicit-content guard passed")
    quit(0)
