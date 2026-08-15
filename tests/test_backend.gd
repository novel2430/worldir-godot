extends SceneTree

func _init() -> void:
    var fixture := _load_json("res://data/fixtures/oweng_semantic_baseline.json")
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var resolved := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    assert(resolved.errors.is_empty(), " | ".join(resolved.errors))
    assert(resolved.regions.size() == 3)
    assert(resolved.networks.size() == 1)
    assert(resolved.entities.size() == 1)
    assert(resolved.distributions.size() == 3)
    assert(resolved.terrain != null)

    for region: ResolvedRegion in resolved.regions:
        assert(region.profile_id == region.semantic_type)
        for key in [
            "terrain", "surface", "distribution_visual_policy", "entity_prototype_policy",
            "path_style", "lighting", "atmosphere", "transition",
        ]:
            assert(region.profile.has(key))

    var crate: ResolvedEntity = resolved.find_entity("supply_crate")
    assert(crate.owner_region_id == "research_region")
    assert(crate.owner_region_type == "research_base")
    assert(crate.prototype_id == "oweng_crate_real")
    var crate_meta := catalog.get_metadata(crate.prototype_id)
    assert(String(crate_meta.semantic_type) == "crate")
    assert((crate_meta.visual_footprint as Vector2).x > 0.0)

    var coastal_trees: ResolvedDistribution = resolved.find_distribution("coastal_trees")
    var snow_trees: ResolvedDistribution = resolved.find_distribution("snow_trees")
    assert(coastal_trees.owner_region_type == "coastal_forest")
    assert(snow_trees.owner_region_type == "snow_forest")
    assert(_prototype_set(coastal_trees) != _prototype_set(snow_trees))
    assert(_all_in_set(coastal_trees, ["oweng_tree_birch", "oweng_tree_pine"]))
    assert(_all_in_set(snow_trees, ["oweng_tree_pine", "oweng_tree_fir"]))

    var repeated := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    assert(repeated.errors.is_empty())
    for distribution: ResolvedDistribution in resolved.distributions:
        var other: ResolvedDistribution = repeated.find_distribution(distribution.id)
        assert(other.instances.size() == distribution.instances.size())
        for index in range(distribution.instances.size()):
            assert((distribution.instances[index].transform as Transform3D).is_equal_approx(
                other.instances[index].transform as Transform3D
            ))
            assert(distribution.instances[index].prototype_id == other.instances[index].prototype_id)

    var candidate := SceneRuntime.new().build_candidate(resolved, catalog)
    assert(candidate != null)
    assert(candidate.get_node_or_null("Entities/supply_crate") != null)
    assert(candidate.get_node("Regions/coastal_region").get_child_count() == 0)
    candidate.free()

    var unsupported: Dictionary = fixture.world_ir.duplicate(true)
    unsupported.entities[0].type = "cabin"
    var failed := WorldBackend.new().lower(unsupported, catalog, 1337)
    assert(not failed.errors.is_empty())
    assert("cabin" in " | ".join(failed.errors))
    assert("research_base" in " | ".join(failed.errors))

    print("WorldIR OwenG backend smoke tests passed")
    quit(0)

func _prototype_set(distribution: ResolvedDistribution) -> Dictionary:
    var result := {}
    for instance: Dictionary in distribution.instances:
        result[String(instance.prototype_id)] = true
    return result

func _all_in_set(distribution: ResolvedDistribution, allowed: Array) -> bool:
    for instance: Dictionary in distribution.instances:
        if String(instance.prototype_id) not in allowed:
            return false
    return true

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
