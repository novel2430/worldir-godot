class_name EntityLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")
const PROTOTYPE_SEED_SALT := 0x50524F54
const POSITION_SEED_SALT := 0x504F5349
const YAW_SEED_SALT := 0x59415700

var binding_resolver = RuntimeBindingResolverScript.new()
var last_error := ""

func lower(
    item: Dictionary,
    catalog: PrototypeCatalog,
    solver: PlacementSolver,
    context: Dictionary,
    binding: Dictionary = {}
) -> ResolvedEntity:
    last_error = ""
    var out := ResolvedEntity.new()
    out.id = String(item.get("id", ""))
    out.semantic_type = String(item.get("type", ""))
    out.prototype_id = catalog.choose_prototype(
        out.semantic_type,
        solver.local_rng(out.id, 0, PROTOTYPE_SEED_SALT)
    )
    if out.prototype_id.is_empty():
        last_error = "Backend capability missing: no TSCN prototype for Entity '%s' (type='%s')" % [out.id, out.semantic_type]
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
    var candidate := solver.try_resolve_candidate(
        placement,
        radius,
        context,
        preferred,
        solver.local_rng(out.id, 0, POSITION_SEED_SALT)
    )
    if not bool(candidate.get("ok", false)):
        last_error = "Placement failed for Entity '%s': %s" % [out.id, String(candidate.get("error", "unknown placement failure"))]
        return null

    var p: Vector2 = candidate["position"]
    solver.register_occupancy(p, radius, out.id)
    var yaw := solver.local_rng(out.id, 0, YAW_SEED_SALT).randf_range(-PI, PI)
    out.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y))
    return out
