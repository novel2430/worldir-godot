extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var backend := WorldBackend.new()

    var baseline: Dictionary = _load_json("res://data/fixtures/oweng_semantic_baseline.json").world_ir
    var resolved := backend.lower(baseline, catalog, 2026)
    assert(resolved.errors.is_empty(), " | ".join(resolved.errors))
    assert(resolved.regions.map(func(region: ResolvedRegion) -> String: return region.semantic_type) == [
        "coastal_forest", "research_base", "snow_forest",
    ])
    assert(resolved.find_entity("supply_crate").owner_region_type == "research_base")
    assert(resolved.find_distribution("snow_trees").owner_region_type == "snow_forest")

    var multi_owner: Dictionary = baseline.duplicate(true)
    multi_owner.distributions[0].placement.relations.append({"type": "inside", "target": "snow_region"})
    var multi_result := backend.lower(multi_owner, catalog, 2026)
    assert(not multi_result.errors.is_empty())
    assert("exactly one" in " | ".join(multi_result.errors))

    var nested: Dictionary = baseline.duplicate(true)
    nested.regions[1].placement = {"relations": [{"type": "inside", "target": "coastal_region"}]}
    var nested_result := backend.lower(nested, catalog, 2026)
    assert(not nested_result.errors.is_empty())
    assert("Region nesting" in " | ".join(nested_result.errors))

    var regions_only := {
        "regions": baseline.regions.duplicate(true),
        "networks": [], "entities": [], "distributions": [],
    }
    var empty_result := backend.lower(regions_only, catalog, 2026)
    assert(empty_result.errors.is_empty())
    assert(empty_result.entities.is_empty())
    assert(empty_result.distributions.is_empty())
    assert(empty_result.decorations.is_empty())

    print("OwenG semantic rebase acceptance tests passed")
    quit(0)

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed
