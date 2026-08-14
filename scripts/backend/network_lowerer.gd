class_name NetworkLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

var binding_resolver = RuntimeBindingResolverScript.new()

func lower(
    item: Dictionary,
    solver: PlacementSolver,
    seed_value: int,
    context: Dictionary,
    binding: Dictionary = {}
) -> ResolvedNetwork:
    var out := ResolvedNetwork.new()
    out.id = String(item.get("id", ""))
    out.semantic_type = String(item.get("type", "road"))
    out.width = 5.5 if out.semantic_type == "road" else 2.5
    out.surface_kind = out.semantic_type

    var topology: Dictionary = item.get("topology", {})
    var start := _topology_point(String(topology.get("from", "south")), solver, context)
    var finish := _topology_point(String(topology.get("to", "north")), solver, context)
    var via: Array = topology.get("via", [])
    var control: Array[Vector2] = [start]
    for token in via:
        control.append(_topology_point(String(token), solver, context))

    var binding_domain: Rect2 = binding_resolver.resolve_domain(
        binding,
        context.get("spatial_payloads", {}),
        solver.world_bounds,
        Vector2(24.0, 24.0)
    )
    if binding_domain.has_area():
        var mode := String(binding.get("placement", "at"))
        if mode == "inside":
            var inside_points := _inside_binding_points(start, finish, binding_domain)
            control = [inside_points[0]]
            for token in via:
                var via_point := _topology_point(String(token), solver, context)
                control.append(_clamp_point(via_point, binding_domain))
            control.append(inside_points[1])
        else:
            control.append(binding_domain.get_center())
            control.append(finish)
    else:
        control.append(finish)

    var local_rng := RandomNumberGenerator.new()
    local_rng.seed = seed_value ^ out.id.hash()
    var points := PackedVector3Array()
    for seg in range(control.size() - 1):
        var a := control[seg]
        var b := control[seg + 1]
        var tangent := (b - a).normalized()
        var normal := Vector2(-tangent.y, tangent.x)
        var steps := 7
        for i in range(steps):
            if seg > 0 and i == 0:
                continue
            var t := float(i) / float(steps - 1)
            var bend := sin(t * PI) * local_rng.randf_range(-5.0, 5.0)
            var p := a.lerp(b, t) + normal * bend
            points.append(Vector3(p.x, 0.08, p.y))
    out.curve_points = points
    return out

func _topology_point(token: String, solver: PlacementSolver, context: Dictionary) -> Vector2:
    if token in ["north", "south", "east", "west", "center", "northwest", "northeast", "southwest", "southeast", "whole"]:
        return solver.anchor_point(token)
    return solver.target_center(token, context)

func _inside_binding_points(start: Vector2, finish: Vector2, domain: Rect2) -> Array[Vector2]:
    var direction := finish - start
    if absf(direction.x) >= absf(direction.y):
        var left := Vector2(domain.position.x + domain.size.x * 0.15, domain.get_center().y)
        var right := Vector2(domain.end.x - domain.size.x * 0.15, domain.get_center().y)
        return [left, right] if direction.x >= 0.0 else [right, left]
    var top := Vector2(domain.get_center().x, domain.position.y + domain.size.y * 0.15)
    var bottom := Vector2(domain.get_center().x, domain.end.y - domain.size.y * 0.15)
    return [top, bottom] if direction.y >= 0.0 else [bottom, top]

func _clamp_point(point: Vector2, domain: Rect2) -> Vector2:
    return Vector2(
        clampf(point.x, domain.position.x, domain.end.x),
        clampf(point.y, domain.position.y, domain.end.y)
    )
