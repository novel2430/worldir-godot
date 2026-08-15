extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var ir := {
        "regions": [
            {"id": "coastal", "type": "coastal_forest", "placement": {"anchor": "west"}},
            {"id": "base", "type": "research_base", "placement": {"anchor": "center"}},
            {"id": "snow", "type": "snow_forest", "placement": {"anchor": "east"}},
        ],
        "networks": [], "entities": [], "distributions": [],
    }
    var first := WorldBackend.new().lower(ir, catalog, 4512)
    var repeated := WorldBackend.new().lower(ir, catalog, 4512)
    assert(first.errors.is_empty() and repeated.errors.is_empty())
    assert(first.regions.size() == 3)
    for region: ResolvedRegion in first.regions:
        var other: ResolvedRegion = repeated.find_region(region.id)
        assert(region.polygon == other.polygon)
        assert(_polygon_area(region.polygon) > 100.0)
    for a in range(first.regions.size()):
        for b in range(a + 1, first.regions.size()):
            assert(_intersection_area(first.regions[a].polygon, first.regions[b].polygon) < 0.01)

    var nested: Dictionary = ir.duplicate(true)
    nested.regions[1].placement = {"relations": [{"type": "inside", "target": "coastal"}]}
    var rejected := WorldBackend.new().lower(nested, catalog, 4512)
    assert(not rejected.errors.is_empty())
    assert("Region nesting" in " | ".join(rejected.errors))
    print("Bounded Region claim tests passed")
    quit(0)

func _polygon_area(polygon: PackedVector2Array) -> float:
    var twice_area := 0.0
    for index in range(polygon.size()):
        twice_area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
    return absf(twice_area * 0.5)

func _intersection_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
    var result := 0.0
    for polygon in Geometry2D.intersect_polygons(a, b):
        result += _polygon_area(polygon)
    return result
