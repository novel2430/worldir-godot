extends SceneTree

var catalog: PrototypeCatalog
var scene_diff := SceneDiff.new()

func _init() -> void:
    catalog = PrototypeCatalog.new()
    root.add_child(catalog)

    var base_ir := _roadside_world_ir(4)
    var base := WorldBackend.new().lower(base_ir, catalog, 4404)
    var repeated := WorldBackend.new().lower(base_ir, catalog, 4404)
    assert(base.errors.is_empty() and repeated.errors.is_empty())
    _test_identical(base, repeated)

    var with_church_ir: Dictionary = base_ir.duplicate(true)
    with_church_ir["entities"].append({
        "id": "church",
        "type": "church",
        "placement": {"anchor": "east"},
    })
    var with_church := WorldBackend.new().lower(with_church_ir, catalog, 4404)
    assert(with_church.errors.is_empty())
    _test_added_entity(base, with_church)

    var moved_church_ir: Dictionary = with_church_ir.duplicate(true)
    moved_church_ir["entities"][0]["placement"] = {"anchor": "west"}
    var moved_church := WorldBackend.new().lower(moved_church_ir, catalog, 4404)
    assert(moved_church.errors.is_empty())
    _test_moved_entity(with_church, moved_church)

    var eight_ir := _roadside_world_ir(8)
    var eight := WorldBackend.new().lower(eight_ir, catalog, 4404)
    assert(eight.errors.is_empty())
    _test_distribution_prefix(base, eight)

    var separated_four := WorldBackend.new().lower(_separated_distributions_ir(4), catalog, 9917)
    var separated_eight := WorldBackend.new().lower(_separated_distributions_ir(8), catalog, 9917)
    assert(separated_four.errors.is_empty() and separated_eight.errors.is_empty())
    _test_object_local_distribution_rng(separated_four, separated_eight)
    _test_manual_replacement_and_geometry_change()
    _test_remaining_resolved_categories()

    print("Stable Resolved SceneDiff tests passed")
    quit(0)

func _test_identical(old_world: ResolvedWorld, new_world: ResolvedWorld) -> void:
    var diff := scene_diff.compare(old_world, new_world)
    assert(_all_change_categories_empty(diff["regions"], ["added", "removed", "changed"]))
    assert(_all_change_categories_empty(diff["networks"], ["added", "removed", "changed"]))
    assert(_all_change_categories_empty(diff["entities"], ["added", "removed", "moved", "replaced"]))
    assert(_all_change_categories_empty(diff["distribution_instances"], ["added", "removed", "moved", "replaced"]))
    assert(_all_change_categories_empty(diff["decoration_instances"], ["added", "removed", "moved", "replaced"]))
    assert(_all_change_categories_empty(diff["waters"], ["added", "removed", "changed"]))
    assert(not diff["terrain_changed"])
    assert(diff["regions"]["unchanged"].size() == old_world.regions.size())
    assert(diff["networks"]["unchanged"].size() == old_world.networks.size())
    assert(diff["distribution_instances"]["unchanged"].size() == 4)

func _test_added_entity(old_world: ResolvedWorld, new_world: ResolvedWorld) -> void:
    var diff := scene_diff.compare(old_world, new_world)
    assert(_ids(diff["entities"]["added"]) == ["church"])
    assert(diff["entities"]["removed"].is_empty())
    assert(diff["entities"]["moved"].is_empty())
    assert(diff["entities"]["replaced"].is_empty())
    assert(_ids(diff["distribution_instances"]["unchanged"]) == [
        "houses:000", "houses:001", "houses:002", "houses:003",
    ])
    assert(diff["distribution_instances"]["moved"].is_empty())
    assert(diff["networks"]["changed"].is_empty())

func _test_moved_entity(old_world: ResolvedWorld, new_world: ResolvedWorld) -> void:
    var diff := scene_diff.compare(old_world, new_world)
    assert(_ids(diff["entities"]["moved"]) == ["church"])
    assert(diff["entities"]["added"].is_empty())
    assert(diff["entities"]["removed"].is_empty())
    assert(diff["entities"]["replaced"].is_empty())

func _test_distribution_prefix(four: ResolvedWorld, eight: ResolvedWorld) -> void:
    var increase := scene_diff.compare(four, eight)
    assert(_ids(increase["distribution_instances"]["unchanged"]) == [
        "houses:000", "houses:001", "houses:002", "houses:003",
    ])
    assert(_ids(increase["distribution_instances"]["added"]) == [
        "houses:004", "houses:005", "houses:006", "houses:007",
    ])
    assert(increase["distribution_instances"]["moved"].is_empty())
    assert(increase["distribution_instances"]["replaced"].is_empty())

    var decrease := scene_diff.compare(eight, four)
    assert(_ids(decrease["distribution_instances"]["unchanged"]) == [
        "houses:000", "houses:001", "houses:002", "houses:003",
    ])
    assert(_ids(decrease["distribution_instances"]["removed"]) == [
        "houses:004", "houses:005", "houses:006", "houses:007",
    ])
    assert(decrease["distribution_instances"]["moved"].is_empty())
    assert(decrease["distribution_instances"]["replaced"].is_empty())

func _test_object_local_distribution_rng(four: ResolvedWorld, eight: ResolvedWorld) -> void:
    var diff: Dictionary = scene_diff.compare(four, eight)["distribution_instances"]
    assert(_ids(diff["added"]) == [
        "trees:004", "trees:005", "trees:006", "trees:007",
    ])
    assert(_ids(diff["unchanged"]) == [
        "houses:000", "houses:001", "houses:002", "houses:003",
        "trees:000", "trees:001", "trees:002", "trees:003",
    ])
    assert(diff["moved"].is_empty())
    assert(diff["replaced"].is_empty())

func _test_manual_replacement_and_geometry_change() -> void:
    var old_world := ResolvedWorld.new()
    var new_world := ResolvedWorld.new()

    var old_distribution := ResolvedDistribution.new()
    old_distribution.id = "trees"
    old_distribution.semantic_type = "tree"
    old_distribution.instances.append({
        "id": "trees:000",
        "prototype_id": "tree_01",
        "transform": Transform3D.IDENTITY,
    })
    var new_distribution := ResolvedDistribution.new()
    new_distribution.id = "trees"
    new_distribution.semantic_type = "tree"
    new_distribution.instances.append({
        "id": "trees:000",
        "prototype_id": "tree_02",
        "transform": Transform3D.IDENTITY,
    })
    old_world.distributions.append(old_distribution)
    new_world.distributions.append(new_distribution)

    var old_network := ResolvedNetwork.new()
    old_network.id = "main_road"
    old_network.curve_points = PackedVector3Array([
        Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, 10.0),
    ])
    var new_network := ResolvedNetwork.new()
    new_network.id = "main_road"
    new_network.curve_points = PackedVector3Array([
        Vector3(0.0, 0.0, -10.0), Vector3(4.0, 0.0, 10.0),
    ])
    old_world.networks.append(old_network)
    new_world.networks.append(new_network)

    var diff := scene_diff.compare(old_world, new_world)
    assert(_ids(diff["distribution_instances"]["replaced"]) == ["trees:000"])
    assert(diff["distribution_instances"]["moved"].is_empty())
    assert(_ids(diff["networks"]["changed"]) == ["main_road"])

func _test_remaining_resolved_categories() -> void:
    var old_world := ResolvedWorld.new()
    var new_world := ResolvedWorld.new()

    var old_region := ResolvedRegion.new()
    old_region.id = "forest"
    old_region.semantic_type = "forest"
    old_region.surface_kind = "forest"
    old_region.polygon = PackedVector2Array([
        Vector2.ZERO, Vector2(10.0, 0.0), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
    ])
    var new_region := ResolvedRegion.new()
    new_region.id = "forest"
    new_region.semantic_type = "forest"
    new_region.surface_kind = "forest"
    new_region.polygon = old_region.polygon.duplicate()
    new_region.polygon[2] += Vector2(1.0, 0.0)
    old_world.regions.append(old_region)
    new_world.regions.append(new_region)

    var old_decoration := ResolvedDecoration.new()
    old_decoration.id = "forest_grass"
    old_decoration.region_id = "forest"
    old_decoration.decoration_type = "grass"
    old_decoration.instances.append({
        "id": "forest_grass:000",
        "prototype_id": "grass_01",
        "transform": Transform3D.IDENTITY,
    })
    var new_decoration := ResolvedDecoration.new()
    new_decoration.id = "forest_grass"
    new_decoration.region_id = "forest"
    new_decoration.decoration_type = "grass"
    new_decoration.instances.append({
        "id": "forest_grass:000",
        "prototype_id": "grass_01",
        "transform": Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)),
    })
    old_world.decorations.append(old_decoration)
    new_world.decorations.append(new_decoration)

    var old_water := ResolvedWater.new()
    old_water.id = "ocean"
    old_water.source_region_id = "coast"
    old_water.shoreline = PackedVector2Array([Vector2.ZERO, Vector2(0.0, 10.0)])
    old_water.polygon = old_water.shoreline.duplicate()
    var new_water := ResolvedWater.new()
    new_water.id = "ocean"
    new_water.source_region_id = "coast"
    new_water.shoreline = PackedVector2Array([Vector2.ZERO, Vector2(1.0, 10.0)])
    new_water.polygon = new_water.shoreline.duplicate()
    old_world.waters.append(old_water)
    new_world.waters.append(new_water)

    old_world.terrain = _terrain_with_height(0.0)
    new_world.terrain = _terrain_with_height(0.1)
    var diff := scene_diff.compare(old_world, new_world)
    assert(_ids(diff["regions"]["changed"]) == ["forest"])
    assert(_ids(diff["decoration_instances"]["moved"]) == ["forest_grass:000"])
    assert(_ids(diff["waters"]["changed"]) == ["ocean"])
    assert(diff["terrain_changed"])

func _terrain_with_height(last_height: float) -> ResolvedTerrain:
    var terrain := ResolvedTerrain.new()
    terrain.world_bounds = Rect2(0.0, 0.0, 1.0, 1.0)
    terrain.grid_size = 2
    terrain.heights = PackedFloat32Array([0.0, 0.0, 0.0, last_height])
    terrain.surface_masks = PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK])
    terrain.shore_wetness = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
    return terrain

func _roadside_world_ir(house_count: int) -> Dictionary:
    return {
        "regions": [
            {"id": "town", "type": "town", "placement": {"anchor": "center"}},
        ],
        "networks": [{
            "id": "main_road",
            "type": "road",
            "topology": {"from": "south", "to": "north"},
        }],
        "entities": [],
        "distributions": [{
            "id": "houses",
            "type": "house",
            "placement": {"relations": [{"type": "along", "target": "main_road"}]},
            "population": {"amount": {"mode": "count", "value": house_count}},
        }],
    }

func _separated_distributions_ir(tree_count: int) -> Dictionary:
    return {
        "regions": [
            {"id": "forest", "type": "forest", "placement": {"anchor": "west"}},
            {"id": "town", "type": "town", "placement": {"anchor": "east"}},
        ],
        "networks": [],
        "entities": [],
        "distributions": [
            {
                "id": "trees",
                "type": "tree",
                "placement": {"relations": [{"type": "inside", "target": "forest"}]},
                "population": {
                    "amount": {"mode": "count", "value": tree_count},
                    "arrangement": {"type": "random"},
                },
            },
            {
                "id": "houses",
                "type": "house",
                "placement": {"relations": [{"type": "inside", "target": "town"}]},
                "population": {
                    "amount": {"mode": "count", "value": 4},
                    "arrangement": {"type": "random"},
                },
            },
        ],
    }

func _ids(records: Array) -> Array[String]:
    var result: Array[String] = []
    for record: Dictionary in records:
        result.append(String(record["id"]))
    return result

func _all_change_categories_empty(bucket: Dictionary, categories: Array[String]) -> bool:
    for category in categories:
        if not (bucket[category] as Array).is_empty():
            return false
    return true
