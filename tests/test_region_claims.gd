extends SceneTree

var catalog: PrototypeCatalog

func _init() -> void:
    catalog = PrototypeCatalog.new()
    root.add_child(catalog)
    _test_anchored_bounded_claims()
    _test_input_order_does_not_choose_winner()
    _test_contested_claims_keep_both_regions()
    _test_near_claim_uses_landward_side()
    _test_inside_is_hierarchical_overlap()
    _test_budget_configuration_changes_spread()
    print("Bounded Region claim tests passed")
    quit(0)

func _test_anchored_bounded_claims() -> void:
    var world := WorldBackend.new().lower(_anchored_ir(false), catalog, 4512)
    assert(world.errors.is_empty())
    var forest := world.find_region("forest")
    var coast := world.find_region("coast")
    assert(forest != null and coast != null)
    assert(_touches_edge(forest.polygon, world.world_bounds, "west"))
    assert(_touches_edge(coast.polygon, world.world_bounds, "east"))
    assert(_intersection_area(forest.polygon, coast.polygon) < 0.01)
    var claimed_area := _polygon_area(forest.polygon) + _polygon_area(coast.polygon)
    # Fixed budgets deliberately leave base meadow instead of balancing two
    # anchors across the complete world.
    assert(claimed_area < world.world_bounds.get_area() * 0.72)
    assert(claimed_area > world.world_bounds.get_area() * 0.15)

func _test_input_order_does_not_choose_winner() -> void:
    var forward := WorldBackend.new().lower(_anchored_ir(false), catalog, 4512)
    var reversed := WorldBackend.new().lower(_anchored_ir(true), catalog, 4512)
    assert(forward.errors.is_empty() and reversed.errors.is_empty())
    for object_id in ["forest", "coast"]:
        var a: ResolvedRegion = forward.find_region(object_id)
        var b: ResolvedRegion = reversed.find_region(object_id)
        assert(_polygons_equal(a.polygon, b.polygon))

func _test_contested_claims_keep_both_regions() -> void:
    var ir := {
        "regions": [
            {"id": "town_a", "type": "town", "placement": {"anchor": "center"}},
            {"id": "town_b", "type": "town", "placement": {"anchor": "center"}},
        ],
        "networks": [], "entities": [], "distributions": [],
    }
    var world := WorldBackend.new().lower(ir, catalog, 6006)
    assert(world.errors.is_empty())
    var town_a := world.find_region("town_a")
    var town_b := world.find_region("town_b")
    assert(town_a != null and town_b != null)
    assert(_polygon_area(town_a.polygon) > 100.0)
    assert(_polygon_area(town_b.polygon) > 100.0)
    assert(_intersection_area(town_a.polygon, town_b.polygon) < 0.01)
    assert(_distance_between_polygons(town_a.polygon, town_b.polygon) <= 0.05)

func _test_near_claim_uses_landward_side() -> void:
    var ir := {
        "regions": [
            {
                "id": "town",
                "type": "town",
                "placement": {"relations": [{"type": "near", "target": "coast"}]},
            },
            {"id": "coast", "type": "coast", "placement": {"anchor": "east"}},
        ],
        "networks": [], "entities": [], "distributions": [],
    }
    var first := WorldBackend.new().lower(ir, catalog, 9090)
    var repeated := WorldBackend.new().lower(ir, catalog, 9090)
    assert(first.errors.is_empty() and repeated.errors.is_empty())
    var town := first.find_region("town")
    var coast := first.find_region("coast")
    assert(town != null and coast != null)
    assert(_polygon_center(town.polygon).x < _polygon_center(coast.polygon).x)
    assert(_intersection_area(town.polygon, coast.polygon) < 0.01)
    assert(_distance_between_polygons(town.polygon, coast.polygon) <= 0.05)
    assert(_polygons_equal(town.polygon, repeated.find_region("town").polygon))

func _test_inside_is_hierarchical_overlap() -> void:
    var parent_only_ir := {
        "regions": [{"id": "forest", "type": "forest", "placement": {"anchor": "west"}}],
        "networks": [], "entities": [], "distributions": [],
    }
    var nested_ir: Dictionary = parent_only_ir.duplicate(true)
    nested_ir.regions.append({
        "id": "graveyard",
        "type": "graveyard",
        "placement": {
            "anchor": "northwest",
            "relations": [{"type": "inside", "target": "forest"}],
        },
    })
    var parent_only := WorldBackend.new().lower(parent_only_ir, catalog, 31337)
    var nested := WorldBackend.new().lower(nested_ir, catalog, 31337)
    assert(parent_only.errors.is_empty() and nested.errors.is_empty())
    var forest := nested.find_region("forest")
    var graveyard := nested.find_region("graveyard")
    assert(_polygons_equal(parent_only.find_region("forest").polygon, forest.polygon))
    assert(_polygon_inside(graveyard.polygon, forest.polygon))
    assert(_intersection_area(graveyard.polygon, forest.polygon) > _polygon_area(graveyard.polygon) * 0.99)

func _test_budget_configuration_changes_spread() -> void:
    var ir := {
        "regions": [{"id": "forest", "type": "forest", "placement": {"anchor": "west"}}],
        "networks": [], "entities": [], "distributions": [],
    }
    var small := WorldBackend.new({
        "region_claim_budgets_m2": {"forest": 1800.0},
    }).lower(ir, catalog, 77)
    var large := WorldBackend.new({
        "region_claim_budgets_m2": {"forest": 7600.0},
    }).lower(ir, catalog, 77)
    assert(small.errors.is_empty() and large.errors.is_empty())
    assert(_polygon_area(small.find_region("forest").polygon) < _polygon_area(large.find_region("forest").polygon) * 0.55)

func _anchored_ir(reversed: bool) -> Dictionary:
    var regions := [
        {"id": "forest", "type": "forest", "placement": {"anchor": "west"}},
        {"id": "coast", "type": "coast", "placement": {"anchor": "east"}},
    ]
    if reversed:
        regions.reverse()
    return {"regions": regions, "networks": [], "entities": [], "distributions": []}

func _touches_edge(polygon: PackedVector2Array, bounds: Rect2, edge: String) -> bool:
    for point in polygon:
        match edge:
            "west":
                if is_equal_approx(point.x, bounds.position.x): return true
            "east":
                if is_equal_approx(point.x, bounds.end.x): return true
            "north":
                if is_equal_approx(point.y, bounds.position.y): return true
            "south":
                if is_equal_approx(point.y, bounds.end.y): return true
    return false

func _polygons_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
    if a.size() != b.size():
        return false
    for index in range(a.size()):
        if not a[index].is_equal_approx(b[index]):
            return false
    return true

func _polygon_inside(source: PackedVector2Array, target: PackedVector2Array) -> bool:
    for point in source:
        if not Geometry2D.is_point_in_polygon(point, target):
            return false
    return true

func _intersection_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
    var area := 0.0
    for polygon in Geometry2D.intersect_polygons(a, b):
        area += _polygon_area(polygon)
    return area

func _distance_between_polygons(a: PackedVector2Array, b: PackedVector2Array) -> float:
    var best := INF
    for point in a:
        for index in range(b.size()):
            best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(
                point,
                b[index],
                b[(index + 1) % b.size()]
            )))
    for point in b:
        for index in range(a.size()):
            best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(
                point,
                a[index],
                a[(index + 1) % a.size()]
            )))
    return best

func _polygon_center(polygon: PackedVector2Array) -> Vector2:
    var center := Vector2.ZERO
    for point in polygon:
        center += point
    return center / float(polygon.size())

func _polygon_area(polygon: PackedVector2Array) -> float:
    var area := 0.0
    for index in range(polygon.size()):
        area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
    return absf(area * 0.5)
