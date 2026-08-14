class_name EntityLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

var binding_resolver = RuntimeBindingResolverScript.new()

func lower(
    item: Dictionary,
    catalog: PrototypeCatalog,
    solver: PlacementSolver,
    context: Dictionary,
    binding: Dictionary = {}
) -> ResolvedEntity:
    var out := ResolvedEntity.new()
    out.id = String(item.get("id", ""))
    out.semantic_type = String(item.get("type", ""))
    out.prototype_id = catalog.choose_prototype(out.semantic_type)
    if out.prototype_id.is_empty():
        return null

    var meta := catalog.get_metadata(out.prototype_id)
    var radius := float(meta.get("placement_radius", 1.0)) + float(meta.get("clearance", 0.0))
    var placement: Dictionary = item.get("placement", {})
    var preferred: Rect2 = binding_resolver.resolve_domain(
        binding,
        context.get("spatial_payloads", {}),
        solver.world_bounds,
        Vector2(maxf(6.0, radius * 2.0), maxf(6.0, radius * 2.0))
    )
    var p := solver.resolve_candidate(placement, radius, context, preferred)
    solver.register_occupancy(p, radius, out.id)
    var yaw := solver.rng.randf_range(-PI, PI)
    out.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y))
    return out
