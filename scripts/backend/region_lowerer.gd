class_name RegionLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

# Runtime payloads remain authoritative geometry. This size is only the fallback
# used by the existing binding resolver when a payload has no explicit AABB.
const BINDING_FALLBACK_SIZE: Vector2 = Vector2(30.0, 30.0)
const EDGE_SEGMENTS: int = 14
const REGION_NOISE_RATIO: float = 0.10
const REGION_NOISE_MIN_M: float = 2.0
const REGION_NOISE_MAX_M: float = 8.0
const LARGE_SCALE_TYPES: Array[String] = ["forest", "coast", "swamp", "field"]

var binding_resolver = RuntimeBindingResolverScript.new()
var last_error: String = ""

func lower(
    item: Dictionary,
    solver: PlacementSolver,
    binding: Dictionary = {},
    spatial_payloads: Dictionary = {},
    context: Dictionary = {}
) -> ResolvedRegion:
    last_error = ""
    var out: ResolvedRegion = ResolvedRegion.new()
    out.id = String(item.get("id", ""))
    out.semantic_type = String(item.get("type", "region"))

    var placement: Dictionary = item.get("placement", {})
    var binding_rect: Rect2 = binding_resolver.resolve_domain(
        binding,
        spatial_payloads,
        solver.world_bounds,
        BINDING_FALLBACK_SIZE
    )

    # Runtime spatial payloads are exact local facts. Do not proceduralize their
    # boundary: the whole point of the binding is to reuse the player's real area.
    if binding_rect.has_area():
        var constrained_binding: Rect2 = solver.placement_domain(placement, context, binding_rect)
        if not constrained_binding.has_area():
            last_error = "Placement failed for Region '%s': Runtime Binding conflicts with IR placement" % out.id
            return null
        out.polygon = _rect_polygon(constrained_binding)
        out.surface_kind = out.semantic_type
        return out

    var rect: Rect2 = _resolve_semantic_rect(out.semantic_type, placement, solver, context)
    if not rect.has_area():
        last_error = "Placement failed for Region '%s': no geometry satisfies all placement constraints" % out.id
        return null

    var inside_target: String = _relation_target(placement.get("relations", []), "inside")
    var inside_region: ResolvedRegion = context.get("regions", {}).get(inside_target)
    if inside_region != null:
        rect = _fit_rect_inside_polygon(rect, inside_region.polygon)
        if not rect.has_area():
            last_error = "Placement failed for Region '%s': footprint cannot fit inside Region '%s'" % [out.id, inside_target]
            return null

    var coast_edge: String = _coast_edge_direction(out.semantic_type, placement)
    if not coast_edge.is_empty():
        rect = _attach_rect_to_edge(rect, coast_edge, solver.world_bounds)

    var base_seed: int = int(context.get("seed", 0))
    var region_seed: int = base_seed ^ int(out.id.hash())
    out.polygon = _irregular_polygon(rect, solver.world_bounds, region_seed, coast_edge)

    if inside_region != null and not _polygon_inside(out.polygon, inside_region.polygon):
        # Irregularization is inward-only, so this should be rare. Preserve the
        # semantic constraint rather than accepting decorative noise that escapes.
        out.polygon = _rect_polygon(rect)

    out.surface_kind = out.semantic_type
    return out

func _resolve_semantic_rect(
    semantic_type: String,
    placement: Dictionary,
    solver: PlacementSolver,
    context: Dictionary
) -> Rect2:
    var relations: Array = placement.get("relations", [])
    var inside_target: String = _relation_target(relations, "inside")

    # Environmental Regions are territories, not 30x30 objects. A simple anchor
    # or direction_of relation is enough to define a large-scale preference field.
    if _is_large_scale(semantic_type) and inside_target.is_empty() and _field_relations_only(relations):
        var field_rect: Rect2 = _large_scale_preference_rect(semantic_type, placement, solver, context)
        if field_rect.has_area():
            return field_rect

    var region_size: Vector2 = _region_size_prior(semantic_type, solver.world_bounds.size)
    var preferred: Rect2 = Rect2()

    if not inside_target.is_empty():
        var target_region: ResolvedRegion = context.get("regions", {}).get(inside_target)
        if target_region == null:
            return Rect2()
        var target_rect: Rect2 = solver.polygon_aabb(target_region.polygon)
        region_size = Vector2(
            minf(region_size.x, target_rect.size.x * 0.55),
            minf(region_size.y, target_rect.size.y * 0.55)
        )
        preferred = _center_domain_for_contained_rect(target_rect, region_size)
        if not preferred.has_area():
            return Rect2()

    if placement.has("anchor"):
        var anchor_rect: Rect2 = solver.anchor_rect(String(placement.get("anchor", "whole")))
        var anchor_size: Vector2 = Vector2(
            minf(region_size.x, anchor_rect.size.x * 0.96),
            minf(region_size.y, anchor_rect.size.y * 0.96)
        )
        region_size = anchor_size
        var anchor_domain: Rect2 = _center_domain_for_contained_rect(anchor_rect, region_size)
        preferred = anchor_domain if not preferred.has_area() else solver.intersect_rect(preferred, anchor_domain)
        if not preferred.has_area():
            return Rect2()

    var direction_relation: Dictionary = _first_relation(relations, "direction_of")
    if not direction_relation.is_empty():
        var direction_zone: Rect2 = _direction_zone_rect(
            String(direction_relation.get("target", "")),
            String(direction_relation.get("direction", "")),
            solver,
            context
        )
        var direction_domain: Rect2 = _center_domain_for_contained_rect(direction_zone, region_size)
        preferred = direction_domain if not preferred.has_area() else solver.intersect_rect(preferred, direction_domain)
        if not preferred.has_area():
            return Rect2()

    if relations.is_empty() and not placement.has("anchor"):
        var center: Vector2 = solver.world_bounds.get_center()
        return _clamp_rect(Rect2(center - region_size * 0.5, region_size), solver.world_bounds)

    var candidate: Dictionary = solver.try_resolve_candidate(placement, 0.0, context, preferred)
    if not bool(candidate.get("ok", false)):
        return Rect2()

    var center_point: Vector2 = candidate["position"]
    return _clamp_rect(Rect2(center_point - region_size * 0.5, region_size), solver.world_bounds)

func _large_scale_preference_rect(
    semantic_type: String,
    placement: Dictionary,
    solver: PlacementSolver,
    context: Dictionary
) -> Rect2:
    var anchor: String = String(placement.get("anchor", ""))
    if not anchor.is_empty() and anchor != "whole":
        return solver.anchor_rect(anchor)
    if anchor == "whole":
        return solver.world_bounds

    var relation: Dictionary = _first_relation(placement.get("relations", []), "direction_of")
    if relation.is_empty():
        return Rect2()
    return _directional_field_rect(
        semantic_type,
        String(relation.get("target", "")),
        String(relation.get("direction", "")),
        solver,
        context
    )

func _directional_field_rect(
    semantic_type: String,
    target: String,
    direction: String,
    solver: PlacementSolver,
    context: Dictionary
) -> Rect2:
    var bounds: Rect2 = solver.world_bounds
    var center: Vector2 = solver.target_center(target, context)
    var gap_x: float = bounds.size.x * 0.04
    var gap_y: float = bounds.size.y * 0.04
    var cross_w: float = bounds.size.x * 0.92
    var cross_h: float = bounds.size.y * 0.92
    var max_horizontal_fraction: float = 0.38 if semantic_type == "coast" else 0.48
    var max_vertical_fraction: float = 0.38 if semantic_type == "coast" else 0.48

    match direction:
        "west":
            var right: float = minf(center.x - gap_x, bounds.position.x + bounds.size.x * max_horizontal_fraction)
            right = maxf(right, bounds.position.x + bounds.size.x * 0.28)
            return Rect2(
                Vector2(bounds.position.x, clampf(center.y - cross_h * 0.5, bounds.position.y, bounds.end.y - cross_h)),
                Vector2(right - bounds.position.x, cross_h)
            )
        "east":
            var left: float = maxf(center.x + gap_x, bounds.end.x - bounds.size.x * max_horizontal_fraction)
            left = minf(left, bounds.end.x - bounds.size.x * 0.28)
            return Rect2(
                Vector2(left, clampf(center.y - cross_h * 0.5, bounds.position.y, bounds.end.y - cross_h)),
                Vector2(bounds.end.x - left, cross_h)
            )
        "north":
            var bottom: float = minf(center.y - gap_y, bounds.position.y + bounds.size.y * max_vertical_fraction)
            bottom = maxf(bottom, bounds.position.y + bounds.size.y * 0.28)
            return Rect2(
                Vector2(clampf(center.x - cross_w * 0.5, bounds.position.x, bounds.end.x - cross_w), bounds.position.y),
                Vector2(cross_w, bottom - bounds.position.y)
            )
        "south":
            var top: float = maxf(center.y + gap_y, bounds.end.y - bounds.size.y * max_vertical_fraction)
            top = minf(top, bounds.end.y - bounds.size.y * 0.28)
            return Rect2(
                Vector2(clampf(center.x - cross_w * 0.5, bounds.position.x, bounds.end.x - cross_w), top),
                Vector2(cross_w, bounds.end.y - top)
            )
    return Rect2()

func _direction_zone_rect(target: String, direction: String, solver: PlacementSolver, context: Dictionary) -> Rect2:
    var bounds: Rect2 = solver.world_bounds
    var center: Vector2 = solver.target_center(target, context)
    match direction:
        "west": return Rect2(bounds.position, Vector2(maxf(0.0, center.x - bounds.position.x), bounds.size.y))
        "east": return Rect2(Vector2(center.x, bounds.position.y), Vector2(maxf(0.0, bounds.end.x - center.x), bounds.size.y))
        "north": return Rect2(bounds.position, Vector2(bounds.size.x, maxf(0.0, center.y - bounds.position.y)))
        "south": return Rect2(Vector2(bounds.position.x, center.y), Vector2(bounds.size.x, maxf(0.0, bounds.end.y - center.y)))
        "northwest": return Rect2(bounds.position, Vector2(maxf(0.0, center.x - bounds.position.x), maxf(0.0, center.y - bounds.position.y)))
        "northeast": return Rect2(Vector2(center.x, bounds.position.y), Vector2(maxf(0.0, bounds.end.x - center.x), maxf(0.0, center.y - bounds.position.y)))
        "southwest": return Rect2(Vector2(bounds.position.x, center.y), Vector2(maxf(0.0, center.x - bounds.position.x), maxf(0.0, bounds.end.y - center.y)))
        "southeast": return Rect2(center, Vector2(maxf(0.0, bounds.end.x - center.x), maxf(0.0, bounds.end.y - center.y)))
    return bounds

func _region_size_prior(semantic_type: String, world_size: Vector2) -> Vector2:
    match semantic_type:
        "forest", "coast", "swamp", "field":
            return Vector2(world_size.x * 0.38, world_size.y * 0.82)
        "town":
            return Vector2(world_size.x * 0.30, world_size.y * 0.38)
        "village":
            return Vector2(world_size.x * 0.24, world_size.y * 0.30)
        "graveyard":
            return Vector2(world_size.x * 0.16, world_size.y * 0.20)
        _:
            return Vector2(world_size.x * 0.24, world_size.y * 0.30)

func _irregular_polygon(rect: Rect2, world_bounds: Rect2, seed_value: int, forced_edge: String) -> PackedVector2Array:
    if not rect.has_area():
        return PackedVector2Array()

    var amplitude: float = clampf(
        minf(rect.size.x, rect.size.y) * REGION_NOISE_RATIO,
        REGION_NOISE_MIN_M,
        REGION_NOISE_MAX_M
    )
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = seed_value
    var points: PackedVector2Array = PackedVector2Array()

    var protect_top: bool = forced_edge == "north" or is_equal_approx(rect.position.y, world_bounds.position.y)
    var protect_right: bool = forced_edge == "east" or is_equal_approx(rect.end.x, world_bounds.end.x)
    var protect_bottom: bool = forced_edge == "south" or is_equal_approx(rect.end.y, world_bounds.end.y)
    var protect_left: bool = forced_edge == "west" or is_equal_approx(rect.position.x, world_bounds.position.x)

    for edge_index in range(4):
        for i in range(EDGE_SEGMENTS):
            var t: float = float(i) / float(EDGE_SEGMENTS)
            var envelope: float = sin(PI * t)
            var offset: float = amplitude * rng.randf_range(0.30, 1.0) * envelope
            var p: Vector2 = Vector2.ZERO
            match edge_index:
                0:
                    p = Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y + (0.0 if protect_top else offset))
                1:
                    p = Vector2(rect.end.x - (0.0 if protect_right else offset), lerpf(rect.position.y, rect.end.y, t))
                2:
                    p = Vector2(lerpf(rect.end.x, rect.position.x, t), rect.end.y - (0.0 if protect_bottom else offset))
                3:
                    p = Vector2(rect.position.x + (0.0 if protect_left else offset), lerpf(rect.end.y, rect.position.y, t))
            p.x = clampf(p.x, world_bounds.position.x, world_bounds.end.x)
            p.y = clampf(p.y, world_bounds.position.y, world_bounds.end.y)
            points.append(p)
    return points

func _coast_edge_direction(semantic_type: String, placement: Dictionary) -> String:
    if semantic_type != "coast":
        return ""
    var anchor: String = String(placement.get("anchor", ""))
    if anchor in ["north", "south", "east", "west"]:
        return anchor
    var direction_relation: Dictionary = _first_relation(placement.get("relations", []), "direction_of")
    var direction: String = String(direction_relation.get("direction", ""))
    if direction in ["north", "south", "east", "west"]:
        return direction
    return ""

func _attach_rect_to_edge(rect: Rect2, edge: String, bounds: Rect2) -> Rect2:
    var out: Rect2 = _clamp_rect(rect, bounds)
    match edge:
        "west": out.position.x = bounds.position.x
        "east": out.position.x = bounds.end.x - out.size.x
        "north": out.position.y = bounds.position.y
        "south": out.position.y = bounds.end.y - out.size.y
    return _clamp_rect(out, bounds)

func _fit_rect_inside_polygon(rect: Rect2, polygon: PackedVector2Array) -> Rect2:
    var current: Rect2 = rect
    for _attempt in range(10):
        if _rect_inside_polygon(current, polygon):
            return current
        var next_size: Vector2 = current.size * 0.84
        if next_size.x < 4.0 or next_size.y < 4.0:
            break
        current = Rect2(current.get_center() - next_size * 0.5, next_size)
    return Rect2()

func _rect_inside_polygon(rect: Rect2, polygon: PackedVector2Array) -> bool:
    var inset: float = 0.02
    var corners: Array[Vector2] = [
        rect.position + Vector2(inset, inset),
        Vector2(rect.end.x - inset, rect.position.y + inset),
        rect.end - Vector2(inset, inset),
        Vector2(rect.position.x + inset, rect.end.y - inset),
    ]
    for corner in corners:
        if not Geometry2D.is_point_in_polygon(corner, polygon):
            return false
    return true

func _polygon_inside(source: PackedVector2Array, target: PackedVector2Array) -> bool:
    for point in source:
        if not Geometry2D.is_point_in_polygon(point, target):
            return false
    return true

func _rect_polygon(rect: Rect2) -> PackedVector2Array:
    return PackedVector2Array([
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y),
    ])

func _center_domain_for_contained_rect(container: Rect2, child_size: Vector2) -> Rect2:
    var half: Vector2 = child_size * 0.5
    var position: Vector2 = container.position + half
    var size: Vector2 = container.size - child_size
    if size.x <= 0.0 or size.y <= 0.0:
        return Rect2()
    return Rect2(position, size)

func _field_relations_only(relations: Array) -> bool:
    for raw_relation in relations:
        var relation: Dictionary = raw_relation
        if String(relation.get("type", "")) != "direction_of":
            return false
    return true

func _first_relation(relations: Array, kind: String) -> Dictionary:
    for raw_relation in relations:
        var relation: Dictionary = raw_relation
        if String(relation.get("type", "")) == kind:
            return relation
    return {}

func _relation_target(relations: Array, kind: String) -> String:
    var relation: Dictionary = _first_relation(relations, kind)
    return String(relation.get("target", ""))

func _is_large_scale(semantic_type: String) -> bool:
    return semantic_type in LARGE_SCALE_TYPES

func _clamp_rect(rect: Rect2, bounds: Rect2) -> Rect2:
    var size: Vector2 = Vector2(minf(rect.size.x, bounds.size.x), minf(rect.size.y, bounds.size.y))
    var pos: Vector2 = rect.position
    pos.x = clampf(pos.x, bounds.position.x, bounds.end.x - size.x)
    pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - size.y)
    return Rect2(pos, size)
