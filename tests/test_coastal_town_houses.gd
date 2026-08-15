extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var ir := _reported_ir()
    var first := WorldBackend.new().lower(ir, catalog, 1337)
    var repeated := WorldBackend.new().lower(ir, catalog, 1337)
    assert(first.errors.is_empty() and repeated.errors.is_empty())

    # Dependency-aware calculation must not reorder the public Resolved collection.
    assert(_region_ids(first) == ["abandoned_seaside_town", "forest", "coast"])
    var town: ResolvedRegion = first.find_region("abandoned_seaside_town")
    var coast: ResolvedRegion = first.find_region("coast")
    var water: ResolvedWater = first.waters[0] if not first.waters.is_empty() else null
    var houses: ResolvedDistribution = first.find_distribution("houses")
    var repeated_houses: ResolvedDistribution = repeated.find_distribution("houses")
    assert(town != null and coast != null and water != null)
    assert(houses != null and repeated_houses != null and not houses.instances.is_empty())
    # Claim polygons may have overlapping AABBs while sharing only an oblique
    # arbitration edge; their actual semantic territories must not overlap.
    assert(_polygon_intersection_area(town.polygon, coast.polygon) < 0.01)

    for index in range(houses.instances.size()):
        var item: Dictionary = houses.instances[index]
        var transform: Transform3D = item["transform"]
        var point := Vector2(transform.origin.x, transform.origin.z)
        var prototype_id := String(item["prototype_id"])
        var footprint: Vector2 = catalog.get_metadata(prototype_id)["visual_footprint"]
        var visual_radius := footprint.length() * 0.5 * transform.basis.get_scale().x
        assert(Geometry2D.is_point_in_polygon(point, town.polygon))
        assert(not Geometry2D.is_point_in_polygon(point, water.polygon))
        assert(water.signed_distance_to_shore(point) <= -visual_radius)
        assert(item["prototype_id"] == repeated_houses.instances[index]["prototype_id"])
        assert(transform.is_equal_approx(repeated_houses.instances[index]["transform"] as Transform3D))

    var trees: ResolvedDistribution = first.find_distribution("forest_trees")
    assert(trees != null and not trees.instances.is_empty())
    var forest: ResolvedRegion = first.find_region("forest")
    for item in trees.instances:
        var origin: Vector3 = (item["transform"] as Transform3D).origin
        assert(Geometry2D.is_point_in_polygon(Vector2(origin.x, origin.z), forest.polygon))

    # Verify the concrete claimed polygons also survive runtime mesh/node
    # construction, not only backend geometry assertions.
    var runtime := SceneRuntime.new()
    var candidate := runtime.build_candidate(first, catalog)
    assert(candidate != null)
    var house_group := candidate.get_node_or_null("Distributions/houses")
    assert(house_group != null and house_group.get_child_count() == houses.instances.size())
    candidate.free()
    runtime.free()

    print("Coastal town house placement regression tests passed")
    quit(0)

func _reported_ir() -> Dictionary:
    return {
        "distributions": [
            {
                "id": "houses",
                "placement": {"relations": [
                    {"target": "abandoned_seaside_town", "type": "inside"},
                    {"target": "main_road", "type": "along"},
                ]},
                "population": {"amount": {"mode": "density", "value": "medium"}},
                "type": "house",
            },
            {
                "id": "forest_trees",
                "placement": {"relations": [
                    {"target": "forest", "type": "inside"},
                ]},
                "population": {"amount": {"mode": "density", "value": "medium"}},
                "type": "tree",
            },
        ],
        "entities": [],
        "networks": [{
            "id": "main_road",
            "placement": {"relations": [
                {"target": "abandoned_seaside_town", "type": "inside"},
            ]},
            "topology": {"from": "south", "to": "north"},
            "type": "road",
        }],
        "regions": [
            {
                "id": "abandoned_seaside_town",
                "placement": {"relations": [
                    {"target": "coast", "type": "near"},
                ]},
                "type": "town",
            },
            {"id": "forest", "placement": {"anchor": "west"}, "type": "forest"},
            {"id": "coast", "placement": {"anchor": "east"}, "type": "coast"},
        ],
    }

func _region_ids(world: ResolvedWorld) -> Array[String]:
    var result: Array[String] = []
    for region: ResolvedRegion in world.regions:
        result.append(region.id)
    return result

func _polygon_intersection_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
    var result := 0.0
    for polygon in Geometry2D.intersect_polygons(a, b):
        var signed_area := 0.0
        for index in range(polygon.size()):
            signed_area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
        result += absf(signed_area * 0.5)
    return result
