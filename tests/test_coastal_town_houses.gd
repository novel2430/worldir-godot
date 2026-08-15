extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var fixture: Dictionary = JSON.parse_string(
        FileAccess.get_file_as_string("res://data/fixtures/oweng_semantic_baseline.json")
    )
    var first := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    var repeated := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    assert(first.errors.is_empty() and repeated.errors.is_empty())
    for distribution_id in ["coastal_trees", "research_rocks", "snow_trees"]:
        var distribution: ResolvedDistribution = first.find_distribution(distribution_id)
        var other: ResolvedDistribution = repeated.find_distribution(distribution_id)
        assert(distribution != null and other != null)
        assert(not distribution.owner_region_type.is_empty())
        for index in range(distribution.instances.size()):
            assert(distribution.instances[index].prototype_id == other.instances[index].prototype_id)
            assert((distribution.instances[index].transform as Transform3D).is_equal_approx(
                other.instances[index].transform as Transform3D
            ))
    assert(first.find_entity("supply_crate").prototype_id == "oweng_crate_real")
    print("Owner-region prototype policy regression tests passed")
    quit(0)
