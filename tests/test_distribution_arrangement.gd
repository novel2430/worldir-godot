extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    for arrangement in ["random", "uniform", "clustered"]:
        var ir := _world(String(arrangement))
        var first := WorldBackend.new().lower(ir, catalog, 4567)
        var repeated := WorldBackend.new().lower(ir, catalog, 4567)
        assert(first.errors.is_empty() and repeated.errors.is_empty())
        var a: ResolvedDistribution = first.find_distribution("trees")
        var b: ResolvedDistribution = repeated.find_distribution("trees")
        assert(a.owner_region_id == "coastal")
        assert(a.instances.size() == 12 and b.instances.size() == 12)
        for index in range(a.instances.size()):
            assert((a.instances[index].transform as Transform3D).is_equal_approx(
                b.instances[index].transform as Transform3D
            ))
    print("Distribution arrangement tests passed")
    quit(0)

func _world(arrangement: String) -> Dictionary:
    return {
        "regions": [{"id": "coastal", "type": "coastal_forest"}],
        "networks": [], "entities": [],
        "distributions": [{
            "id": "trees", "type": "tree",
            "placement": {"relations": [{"type": "inside", "target": "coastal"}]},
            "population": {
                "amount": {"mode": "count", "value": 12},
                "arrangement": {"type": arrangement},
            },
        }],
    }
