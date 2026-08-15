class_name RegionClaimResolver
extends RefCounted

# Region claims are a backend realization policy. World IR supplies semantic
# anchors and relations; these budgets only decide how far each resolved Region
# can spread before it runs out of influence.
const DEFAULT_REGION_CLAIM_BUDGET_M2 := 3000.0
const DEFAULT_REGION_CLAIM_BUDGETS_M2 := {
    "coastal_forest": 7200.0,
    "research_base": 5200.0,
    "snow_forest": 7200.0,
}
const BOUNDARY_SEGMENTS := 32
const BOUNDARY_VARIATION := 0.055
const MIN_POLYGON_AREA_M2 := 16.0
const SEED_SALT := 0x434C414D

var default_budget_m2 := DEFAULT_REGION_CLAIM_BUDGET_M2
var budgets_m2: Dictionary = DEFAULT_REGION_CLAIM_BUDGETS_M2.duplicate()
var last_error := ""

func configure(values: Dictionary) -> void:
    default_budget_m2 = float(values.get(
        "default_region_claim_budget_m2",
        DEFAULT_REGION_CLAIM_BUDGET_M2
    ))
    budgets_m2 = DEFAULT_REGION_CLAIM_BUDGETS_M2.duplicate()
    for semantic_type in values.get("region_claim_budgets_m2", {}).keys():
        budgets_m2[String(semantic_type)] = float(values.region_claim_budgets_m2[semantic_type])

func apply(
    ordered_items: Array,
    regions_by_id: Dictionary,
    solver: PlacementSolver,
    fixed_region_ids: Dictionary
) -> bool:
    last_error = ""
    if ordered_items.is_empty():
        return true

    var records: Dictionary = {}
    for raw_item in ordered_items:
        var item: Dictionary = raw_item
        var object_id := String(item.get("id", ""))
        var region: ResolvedRegion = regions_by_id.get(object_id)
        if region == null or region.polygon.size() < 3:
            last_error = "Region claim failed for '%s': provisional geometry is missing" % object_id
            return false
        var budget := float(budgets_m2.get(
            region.semantic_type,
            default_budget_m2
        ))
        records[object_id] = {
            "id": object_id,
            "item": item,
            "region": region,
            "parent_id": _inside_target(item),
            "fixed": bool(fixed_region_ids.get(object_id, false)),
            "budget": budget,
            "radius": sqrt(budget / PI),
            "seed": _provisional_center(region.polygon),
        }

    # Anchors create primary seeds. Relation-derived provisional geometry is
    # already dependency-aware, so it remains the seed source for conjunctions.
    for object_id in records.keys():
        var record: Dictionary = records[object_id]
        record.seed = _seed_for(record, solver)

    # A source with only `near` and no anchor is seeded just beyond the target's
    # provisional spread. This makes relation order determine seed availability,
    # not permanent ownership; final conflicts are still arbitrated symmetrically.
    for raw_item in ordered_items:
        var item: Dictionary = raw_item
        var object_id := String(item.get("id", ""))
        var record: Dictionary = records[object_id]
        var near_target := _sole_near_target(item)
        if near_target.is_empty() or not records.has(near_target):
            continue
        record.seed = _near_seed(record, records[near_target], solver)

    for object_id in records.keys():
        var record: Dictionary = records[object_id]
        if bool(record.fixed):
            record.desired = (record.region as ResolvedRegion).polygon.duplicate()
        else:
            record.desired = _claim_polygon(
                record.seed,
                float(record.radius),
                object_id,
                solver
            )

    var root_ids: Array[String] = []
    for raw_item in ordered_items:
        var object_id := String((raw_item as Dictionary).get("id", ""))
        if String((records[object_id] as Dictionary).parent_id).is_empty():
            root_ids.append(object_id)
    if not _resolve_layer(root_ids, records, PackedVector2Array()):
        return false

    var resolved_ids: Dictionary = {}
    for object_id in root_ids:
        resolved_ids[object_id] = true
    var pending: Array[String] = []
    for raw_item in ordered_items:
        var object_id := String((raw_item as Dictionary).get("id", ""))
        if not resolved_ids.has(object_id):
            pending.append(object_id)

    while not pending.is_empty():
        var progressed := false
        var parent_ids: Array[String] = []
        for object_id in pending:
            var parent_id := String((records[object_id] as Dictionary).parent_id)
            if resolved_ids.has(parent_id) and parent_id not in parent_ids:
                parent_ids.append(parent_id)
        for parent_id in parent_ids:
            var sibling_ids: Array[String] = []
            for object_id in pending:
                if String((records[object_id] as Dictionary).parent_id) == parent_id:
                    sibling_ids.append(object_id)
            var parent_polygon: PackedVector2Array = (
                (records[parent_id] as Dictionary).region as ResolvedRegion
            ).polygon
            if not _resolve_layer(sibling_ids, records, parent_polygon):
                return false
            for object_id in sibling_ids:
                resolved_ids[object_id] = true
                pending.erase(object_id)
            progressed = progressed or not sibling_ids.is_empty()
        if not progressed:
            last_error = "Region claim failed: unresolved inside relation cycle"
            return false
    return true

func _resolve_layer(
    object_ids: Array[String],
    records: Dictionary,
    parent_polygon: PackedVector2Array
) -> bool:
    for object_id in object_ids:
        var record: Dictionary = records[object_id]
        var polygon: PackedVector2Array = record.desired

        if not parent_polygon.is_empty():
            if bool(record.fixed):
                if not _polygon_inside(polygon, parent_polygon):
                    last_error = (
                        "Region claim failed for '%s': Runtime Binding conflicts with inside parent '%s'"
                        % [object_id, String(record.parent_id)]
                    )
                    return false
            else:
                polygon = _largest_polygon(Geometry2D.intersect_polygons(
                    polygon,
                    parent_polygon
                ))

        if not bool(record.fixed):
            for other_id in object_ids:
                if other_id == object_id:
                    continue
                var other: Dictionary = records[other_id]
                if bool(other.fixed):
                    polygon = _largest_polygon(Geometry2D.clip_polygons(
                        polygon,
                        (other.region as ResolvedRegion).polygon
                    ), record.seed)
                else:
                    polygon = _clip_against_claim(polygon, record, other)
                if polygon.size() < 3:
                    break

        if polygon.size() < 3 or absf(_polygon_area(polygon)) < MIN_POLYGON_AREA_M2:
            last_error = "Region claim failed for '%s': no territory remains after arbitration" % object_id
            return false
        (record.region as ResolvedRegion).polygon = polygon
    return true

func _clip_against_claim(
    polygon: PackedVector2Array,
    owner: Dictionary,
    competitor: Dictionary
) -> PackedVector2Array:
    if polygon.size() < 3:
        return PackedVector2Array()
    var owner_seed: Vector2 = owner.seed
    var other_seed: Vector2 = competitor.seed
    var normal := 2.0 * (owner_seed - other_seed)
    var threshold := (
        float(competitor.radius) * float(competitor.radius)
        - float(owner.radius) * float(owner.radius)
        + owner_seed.length_squared()
        - other_seed.length_squared()
    )
    if normal.length_squared() < 0.000001:
        var owner_wins := (
            float(owner.radius) > float(competitor.radius)
            or (
                is_equal_approx(float(owner.radius), float(competitor.radius))
                and String(owner.id) < String(competitor.id)
            )
        )
        return polygon if owner_wins else PackedVector2Array()
    return _clip_half_plane(polygon, normal, threshold)

func _seed_for(record: Dictionary, solver: PlacementSolver) -> Vector2:
    var item: Dictionary = record.item
    var placement: Dictionary = item.get("placement", {})
    var relations: Array = placement.get("relations", [])
    var seed: Vector2 = record.seed
    if placement.has("anchor") and relations.is_empty():
        var anchor := String(placement.get("anchor", "whole"))
        seed = solver.anchor_point(anchor)
        seed += _anchor_cross_jitter(anchor, String(record.id), solver)
    elif not placement.has("anchor") and relations.is_empty():
        var rng := solver.local_rng(String(record.id), 0, SEED_SALT)
        var angle := rng.randf_range(0.0, TAU)
        var distance := rng.randf_range(0.04, 0.20) * minf(
            solver.world_bounds.size.x,
            solver.world_bounds.size.y
        )
        seed = solver.world_bounds.get_center() + Vector2.from_angle(angle) * distance
    else:
        # Two relation-derived Regions can legitimately receive the same
        # provisional center (for example both east of one target). Give each a
        # small object-local nudge so neither disappears through an exact power
        # tie. Final parent clipping / claim arbitration remains authoritative.
        var rng := solver.local_rng(String(record.id), 0, SEED_SALT ^ 0x52454C41)
        seed += Vector2.from_angle(rng.randf_range(0.0, TAU)) * minf(
            3.0,
            float(record.radius) * 0.10
        )
    return _clamp_seed(seed, solver.world_bounds)

func _near_seed(source: Dictionary, target: Dictionary, solver: PlacementSolver) -> Vector2:
    var target_seed: Vector2 = target.seed
    var direction: Vector2 = (source.seed as Vector2) - target_seed
    if direction.length_squared() < 0.001:
        var rng := solver.local_rng(String(source.id), 0, SEED_SALT ^ 0x4E454152)
        direction = Vector2.from_angle(rng.randf_range(0.0, TAU))
    direction = direction.normalized()
    var separation := (
        float(target.radius) * 0.72
        + float(source.radius) * 0.65
        + clampf(solver.near_threshold_m * 0.25, 2.0, 6.0)
    )
    return _clamp_seed(target_seed + direction * separation, solver.world_bounds)

func _anchor_cross_jitter(anchor: String, object_id: String, solver: PlacementSolver) -> Vector2:
    var rng := solver.local_rng(object_id, 0, SEED_SALT ^ 0x414E4348)
    var amount := rng.randf_range(-0.10, 0.10)
    match anchor:
        "west", "east": return Vector2(0.0, solver.world_bounds.size.y * amount)
        "north", "south": return Vector2(solver.world_bounds.size.x * amount, 0.0)
        "center", "whole": return Vector2(
            solver.world_bounds.size.x * amount * 0.35,
            solver.world_bounds.size.y * rng.randf_range(-0.035, 0.035)
        )
        _:
            return Vector2(
                solver.world_bounds.size.x * amount * 0.25,
                solver.world_bounds.size.y * rng.randf_range(-0.025, 0.025)
            )

func _claim_polygon(
    seed: Vector2,
    radius: float,
    object_id: String,
    solver: PlacementSolver
) -> PackedVector2Array:
    var rng := solver.local_rng(object_id, 0, SEED_SALT ^ 0x504F4C59)
    var phase_a := rng.randf_range(0.0, TAU)
    var phase_b := rng.randf_range(0.0, TAU)
    var samples := PackedVector2Array()
    for index in range(BOUNDARY_SEGMENTS):
        var angle := TAU * float(index) / float(BOUNDARY_SEGMENTS)
        var variation := (
            sin(angle * 3.0 + phase_a) * BOUNDARY_VARIATION
            + sin(angle * 5.0 + phase_b) * BOUNDARY_VARIATION * 0.35
        )
        samples.append(seed + Vector2.from_angle(angle) * radius * (1.0 + variation))
    var polygon := Geometry2D.convex_hull(samples)
    if polygon.size() > 1 and polygon[0].is_equal_approx(polygon[-1]):
        polygon.resize(polygon.size() - 1)
    polygon = _clip_half_plane(polygon, Vector2.RIGHT, solver.world_bounds.position.x)
    polygon = _clip_half_plane(polygon, Vector2.LEFT, -solver.world_bounds.end.x)
    polygon = _clip_half_plane(polygon, Vector2.DOWN, solver.world_bounds.position.y)
    polygon = _clip_half_plane(polygon, Vector2.UP, -solver.world_bounds.end.y)
    return polygon

func _clip_half_plane(
    polygon: PackedVector2Array,
    normal: Vector2,
    threshold: float
) -> PackedVector2Array:
    var result := PackedVector2Array()
    if polygon.is_empty():
        return result
    for index in range(polygon.size()):
        var a := polygon[index]
        var b := polygon[(index + 1) % polygon.size()]
        var a_value := normal.dot(a) - threshold
        var b_value := normal.dot(b) - threshold
        var a_inside := a_value >= -0.0001
        var b_inside := b_value >= -0.0001
        if a_inside:
            result.append(a)
        if a_inside != b_inside:
            var denominator := normal.dot(b - a)
            if absf(denominator) > 0.000001:
                var t := clampf((threshold - normal.dot(a)) / denominator, 0.0, 1.0)
                result.append(a.lerp(b, t))
    return _deduplicate_polygon(result)

func _largest_polygon(polygons: Array, preferred_point: Variant = null) -> PackedVector2Array:
    var largest := PackedVector2Array()
    var largest_area := -1.0
    for raw_polygon in polygons:
        var polygon: PackedVector2Array = raw_polygon
        if preferred_point is Vector2 and Geometry2D.is_point_in_polygon(preferred_point, polygon):
            return polygon
        var area := absf(_polygon_area(polygon))
        if area > largest_area:
            largest = polygon
            largest_area = area
    return largest

func _deduplicate_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
    var result := PackedVector2Array()
    for point in polygon:
        if result.is_empty() or not result[-1].is_equal_approx(point):
            result.append(point)
    if result.size() > 1 and result[0].is_equal_approx(result[-1]):
        result.resize(result.size() - 1)
    return result

func _inside_target(item: Dictionary) -> String:
    for relation in item.get("placement", {}).get("relations", []):
        if String(relation.get("type", "")) == "inside":
            return String(relation.get("target", ""))
    return ""

func _sole_near_target(item: Dictionary) -> String:
    var placement: Dictionary = item.get("placement", {})
    var relations: Array = placement.get("relations", [])
    if placement.has("anchor") or relations.size() != 1:
        return ""
    var relation: Dictionary = relations[0]
    return String(relation.get("target", "")) if String(relation.get("type", "")) == "near" else ""

func _provisional_center(polygon: PackedVector2Array) -> Vector2:
    var minimum := polygon[0]
    var maximum := polygon[0]
    for point in polygon:
        minimum = minimum.min(point)
        maximum = maximum.max(point)
    return (minimum + maximum) * 0.5

func _clamp_seed(seed: Vector2, bounds: Rect2) -> Vector2:
    return Vector2(
        clampf(seed.x, bounds.position.x + 0.1, bounds.end.x - 0.1),
        clampf(seed.y, bounds.position.y + 0.1, bounds.end.y - 0.1)
    )

func _polygon_inside(source: PackedVector2Array, target: PackedVector2Array) -> bool:
    for point in source:
        if not Geometry2D.is_point_in_polygon(point, target):
            return false
    return true

func _polygon_area(polygon: PackedVector2Array) -> float:
    var area := 0.0
    for index in range(polygon.size()):
        area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
    return area * 0.5
