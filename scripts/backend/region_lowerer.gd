class_name RegionLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

const RELATIVE_REGION_SIZE := Vector2(30.0, 30.0)

var binding_resolver = RuntimeBindingResolverScript.new()

func lower(
    item: Dictionary,
    solver: PlacementSolver,
    binding: Dictionary = {},
    spatial_payloads: Dictionary = {},
    context: Dictionary = {}
) -> ResolvedRegion:
    var out := ResolvedRegion.new()
    out.id = String(item.get("id", ""))
    out.semantic_type = String(item.get("type", "region"))

    var rect: Rect2 = binding_resolver.resolve_domain(binding, spatial_payloads, solver.world_bounds, RELATIVE_REGION_SIZE)
    if not rect.has_area():
        var placement: Dictionary = item.get("placement", {})
        rect = _resolve_semantic_rect(placement, solver, context)

    out.polygon = PackedVector2Array([
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y),
    ])
    out.surface_kind = out.semantic_type
    return out

func _resolve_semantic_rect(placement: Dictionary, solver: PlacementSolver, context: Dictionary) -> Rect2:
    var relations: Array = placement.get("relations", [])
    if placement.has("anchor") and relations.is_empty():
        return solver.anchor_rect(String(placement.get("anchor", "whole")))

    var inside_target := _relation_target(relations, "inside")
    var region_size := RELATIVE_REGION_SIZE
    var preferred := Rect2()
    if not inside_target.is_empty():
        var target_rect := _target_region_rect(inside_target, solver, context)
        if target_rect.has_area():
            region_size = Vector2(
                minf(RELATIVE_REGION_SIZE.x, target_rect.size.x * 0.55),
                minf(RELATIVE_REGION_SIZE.y, target_rect.size.y * 0.55)
            )
            preferred = _center_domain_for_contained_rect(target_rect, region_size)

    if not preferred.has_area() and placement.has("anchor"):
        preferred = solver.anchor_rect(String(placement.get("anchor", "whole")))

    if relations.is_empty() and not preferred.has_area():
        var center := solver.anchor_point("center")
        return Rect2(center - RELATIVE_REGION_SIZE * 0.5, RELATIVE_REGION_SIZE)

    var center_point := solver.resolve_candidate(placement, 0.0, context, preferred)
    var rect := Rect2(center_point - region_size * 0.5, region_size)
    if not inside_target.is_empty():
        var inside_rect := _target_region_rect(inside_target, solver, context)
        if inside_rect.has_area():
            rect = _clamp_rect(rect, inside_rect)
            return rect
    return _clamp_rect(rect, solver.world_bounds)

func _target_region_rect(target: String, solver: PlacementSolver, context: Dictionary) -> Rect2:
    var resolved: ResolvedRegion = context.get("regions", {}).get(target)
    if resolved != null:
        return solver.polygon_aabb(resolved.polygon)

    var raw_value: Variant = context.get("ir_objects", {}).get(target)
    if typeof(raw_value) == TYPE_DICTIONARY:
        var raw: Dictionary = raw_value
        var placement: Dictionary = raw.get("placement", {})
        if placement.has("anchor"):
            return solver.anchor_rect(String(placement.get("anchor", "whole")))
        var center := solver.target_center(target, context)
        return Rect2(center - RELATIVE_REGION_SIZE * 0.5, RELATIVE_REGION_SIZE)
    return Rect2()

func _center_domain_for_contained_rect(container: Rect2, child_size: Vector2) -> Rect2:
    var half := child_size * 0.5
    var position := container.position + half
    var size := container.size - child_size
    if size.x <= 0.0 or size.y <= 0.0:
        return Rect2(container.get_center() - Vector2(0.5, 0.5), Vector2.ONE)
    return Rect2(position, size)

func _relation_target(relations: Array, kind: String) -> String:
    for rel in relations:
        if String(rel.get("type", "")) == kind:
            return String(rel.get("target", ""))
    return ""

func _clamp_rect(rect: Rect2, bounds: Rect2) -> Rect2:
    var size := Vector2(minf(rect.size.x, bounds.size.x), minf(rect.size.y, bounds.size.y))
    var pos := rect.position
    pos.x = clampf(pos.x, bounds.position.x, bounds.end.x - size.x)
    pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - size.y)
    return Rect2(pos, size)
