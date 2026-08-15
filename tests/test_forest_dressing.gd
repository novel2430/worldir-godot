extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var regions_only := {
        "regions": [
            {"id": "coast", "type": "coastal_forest", "placement": {"anchor": "west"}},
            {"id": "base", "type": "research_base", "placement": {"anchor": "center"}},
            {"id": "snow", "type": "snow_forest", "placement": {"anchor": "east"}},
        ],
        "networks": [], "entities": [], "distributions": [],
    }
    var empty := WorldBackend.new().lower(regions_only, catalog, 7001)
    assert(empty.errors.is_empty())
    assert(empty.entities.is_empty())
    assert(empty.distributions.is_empty())
    assert(empty.decorations.is_empty())

    var explicit: Dictionary = regions_only.duplicate(true)
    explicit.distributions.append({
        "id": "requested_trees",
        "type": "tree",
        "placement": {"relations": [{"type": "inside", "target": "snow"}]},
        "population": {"amount": {"mode": "count", "value": 4}},
    })
    var realized := WorldBackend.new().lower(explicit, catalog, 7001)
    assert(realized.errors.is_empty())
    assert(realized.distributions.size() == 1)
    assert(realized.find_distribution("requested_trees").instances.size() == 4)
    assert(realized.decorations.is_empty())
    print("Region profiles do not perform semantic completion")
    quit(0)
