class_name PlacementSolver
extends RefCounted

const MAX_ATTEMPTS := 180
const NEAR_THRESHOLD_M := 20.0
const FAR_THRESHOLD_M := 28.0
const ALONG_THRESHOLD_M := 14.0

var world_bounds := Rect2(-80.0, -80.0, 160.0, 160.0)
var rng := RandomNumberGenerator.new()
var occupied: Array = [] # [{position: Vector2, radius: float, id: String}]

func configure(bounds: Rect2, seed_value: int) -> void:
    world_bounds = bounds
    rng.seed = seed_value
    occupied.clear()

func register_occupancy(position: Vector2, radius: float, object_id: String) -> void:
    occupied.append({"position": position, "radius": radius, "id": object_id})

func anchor_rect(anchor: String) -> Rect2:
    var x0 := world_bounds.position.x
    var z0 := world_bounds.position.y
    var w := world_bounds.size.x
    var h := world_bounds.size.y
    match anchor:
        "west": return Rect2(x0, z0, w * 0.38, h)
        "east": return Rect2(x0 + w * 0.62, z0, w * 0.38, h)
        "north": return Rect2(x0, z0, w, h * 0.38)
        "south": return Rect2(x0, z0 + h * 0.62, w, h * 0.38)
        "northwest": return Rect2(x0, z0, w * 0.45, h * 0.45)
        "northeast": return Rect2(x0 + w * 0.55, z0, w * 0.45, h * 0.45)
        "southwest": return Rect2(x0, z0 + h * 0.55, w * 0.45, h * 0.45)
        "southeast": return Rect2(x0 + w * 0.55, z0 + h * 0.55, w * 0.45, h * 0.45)
        "center": return Rect2(x0 + w * 0.28, z0 + h * 0.28, w * 0.44, h * 0.44)
        "whole", "": return world_bounds
        _: return world_bounds

func anchor_point(anchor: String) -> Vector2:
    var r := anchor_rect(anchor)
    return r.position + r.size * 0.5

# Placement.anchor and every inside relation are conjunctive. Runtime/binding domains
# passed as preferred_rect are conjunctive as well rather than silently replacing IR.
func placement_domain(placement: Dictionary, context: Dictionary, preferred_rect: Rect2 = Rect2()) -> Rect2:
    var domain := world_bounds
    if preferred_rect.has_area():
        domain = intersect_rect(domain, preferred_rect)

    var anchor := String(placement.get("anchor", "whole"))
    if anchor != "whole" and not anchor.is_empty():
        domain = intersect_rect(domain, anchor_rect(anchor))

    for rel in placement.get("relations", []):
        if String(rel.get("type", "")) != "inside":
            continue
        var target := String(rel.get("target", ""))
        var region: ResolvedRegion = context.get("regions", {}).get(target)
        if region == null:
            return Rect2()
        domain = intersect_rect(domain, polygon_aabb(region.polygon))
        if not domain.has_area():
            return Rect2()
    return domain

func try_resolve_candidate(
    placement: Dictionary,
    radius: float,
    context: Dictionary,
    preferred_rect: Rect2 = Rect2()
) -> Dictionary:
    var domain := placement_domain(placement, context, preferred_rect)
    if not domain.has_area():
        return {
            "ok": false,
            "error": "Placement constraints have no overlapping spatial domain",
        }

    for _attempt in range(MAX_ATTEMPTS):
        var p := Vector2(
            rng.randf_range(domain.position.x, domain.end.x),
            rng.randf_range(domain.position.y, domain.end.y)
        )
        if is_candidate_valid(p, placement, radius, context):
            return {"ok": true, "position": p}

    return {
        "ok": false,
        "error": "No candidate satisfies all placement relations after %d attempts" % MAX_ATTEMPTS,
    }

func is_candidate_valid(p: Vector2, placement: Dictionary, radius: float, context: Dictionary) -> bool:
    if not is_semantically_valid(p, placement, context):
        return false
    if overlaps(p, radius):
        return false
    return true

func is_semantically_valid(p: Vector2, placement: Dictionary, context: Dictionary) -> bool:
    var relations: Array = placement.get("relations", [])
    for rel in relations:
        if String(rel.get("type", "")) != "inside":
            continue
        var region: ResolvedRegion = context.get("regions", {}).get(String(rel.get("target", "")))
        if region == null or not Geometry2D.is_point_in_polygon(p, region.polygon):
            return false
    return _satisfies_relations(p, relations, context)

func sample_network(network: ResolvedNetwork, t: float, cached_lengths: Array[float] = [], cached_total: float = -1.0) -> Array:
    if network == null or network.curve_points.size() < 2:
        return [Vector2.ZERO, Vector2(0.0, -1.0)]
    var lengths: Array[float] = cached_lengths
    if lengths.is_empty():
        lengths = _polyline_lengths(network.curve_points)
    var total := cached_total
    if total < 0.0:
        total = lengths[-1]
    return _sample_polyline(network.curve_points, lengths, total * clampf(t, 0.0, 1.0))

func overlaps(p: Vector2, radius: float) -> bool:
    for item in occupied:
        var min_dist := radius + float(item.radius)
        if p.distance_squared_to(item.position) < min_dist * min_dist:
            return true
    return false

func overlaps_networks(p: Vector2, radius: float, networks: Array, extra_clearance: float = 0.0) -> bool:
    for network: ResolvedNetwork in networks:
        if network == null or network.curve_points.size() < 2:
            continue
        var required_distance := network.width * 0.5 + radius + extra_clearance
        if p.distance_squared_to(nearest_point_on_network(p, network)) < required_distance * required_distance:
            return true
    return false

func intersect_rect(a: Rect2, b: Rect2) -> Rect2:
    if not a.has_area() or not b.has_area():
        return Rect2()
    var x0 := maxf(a.position.x, b.position.x)
    var y0 := maxf(a.position.y, b.position.y)
    var x1 := minf(a.end.x, b.end.x)
    var y1 := minf(a.end.y, b.end.y)
    if x1 <= x0 or y1 <= y0:
        return Rect2()
    return Rect2(x0, y0, x1 - x0, y1 - y0)

func polygon_aabb(poly: PackedVector2Array) -> Rect2:
    if poly.is_empty():
        return world_bounds
    var min_x := poly[0].x
    var max_x := poly[0].x
    var min_y := poly[0].y
    var max_y := poly[0].y
    for p in poly:
        min_x = minf(min_x, p.x)
        max_x = maxf(max_x, p.x)
        min_y = minf(min_y, p.y)
        max_y = maxf(max_y, p.y)
    return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func nearest_point_on_network(p: Vector2, network: ResolvedNetwork) -> Vector2:
    if network == null or network.curve_points.size() < 2:
        return p
    var best := Vector2(network.curve_points[0].x, network.curve_points[0].z)
    var best_d := INF
    for i in range(network.curve_points.size() - 1):
        var a := Vector2(network.curve_points[i].x, network.curve_points[i].z)
        var b := Vector2(network.curve_points[i + 1].x, network.curve_points[i + 1].z)
        var q := Geometry2D.get_closest_point_to_segment(p, a, b)
        var d := p.distance_squared_to(q)
        if d < best_d:
            best_d = d
            best = q
    return best

func distance_to_target(p: Vector2, target: String, context: Dictionary) -> float:
    var net: ResolvedNetwork = context.get("networks", {}).get(target)
    if net != null:
        return p.distance_to(nearest_point_on_network(p, net))

    var region: ResolvedRegion = context.get("regions", {}).get(target)
    if region != null:
        if Geometry2D.is_point_in_polygon(p, region.polygon):
            return 0.0
        return _distance_to_polygon(p, region.polygon)

    return p.distance_to(target_center(target, context))

func target_center(target: String, context: Dictionary) -> Vector2:
    return _target_center(target, context, {})

func direction_affinity(p: Vector2, target: String, direction: String, context: Dictionary, scale: float) -> float:
    var center := target_center(target, context)
    var delta := p - center
    var axis := _direction_axis(direction)
    if axis == Vector2.ZERO:
        return 0.5
    var safe_scale := maxf(1.0, scale)
    return clampf(0.5 + delta.dot(axis) / safe_scale, 0.0, 1.0)

func _satisfies_relations(p: Vector2, relations: Array, context: Dictionary) -> bool:
    for rel in relations:
        var kind := String(rel.get("type", ""))
        var target := String(rel.get("target", ""))
        match kind:
            "near":
                var near_distance := distance_to_target(p, target, context)
                if near_distance > NEAR_THRESHOLD_M:
                    return false
            "far_from":
                var far_distance := distance_to_target(p, target, context)
                if far_distance < FAR_THRESHOLD_M:
                    return false
            "direction_of":
                var center := target_center(target, context)
                if not _direction_matches(p, center, String(rel.get("direction", ""))):
                    return false
            "along":
                var net: ResolvedNetwork = context.get("networks", {}).get(target)
                if net == null:
                    return false
                if p.distance_to(nearest_point_on_network(p, net)) > ALONG_THRESHOLD_M:
                    return false
            "inside":
                pass
    return true

func _distance_to_polygon(p: Vector2, poly: PackedVector2Array) -> float:
    if poly.size() < 2:
        return INF
    var best := INF
    for i in range(poly.size()):
        var a := poly[i]
        var b := poly[(i + 1) % poly.size()]
        var q := Geometry2D.get_closest_point_to_segment(p, a, b)
        best = minf(best, p.distance_to(q))
    return best

func _target_center(target: String, context: Dictionary, visiting: Dictionary) -> Vector2:
    var region: ResolvedRegion = context.get("regions", {}).get(target)
    if region != null:
        var region_rect := polygon_aabb(region.polygon)
        return region_rect.get_center()

    var entity: ResolvedEntity = context.get("entities", {}).get(target)
    if entity != null:
        return Vector2(entity.transform.origin.x, entity.transform.origin.z)

    var net: ResolvedNetwork = context.get("networks", {}).get(target)
    if net != null and not net.curve_points.is_empty():
        var mid := net.curve_points[net.curve_points.size() / 2]
        return Vector2(mid.x, mid.z)

    var distribution: ResolvedDistribution = context.get("distributions", {}).get(target)
    if distribution != null and not distribution.instances.is_empty():
        var sum := Vector2.ZERO
        for instance in distribution.instances:
            var transform: Transform3D = instance.get("transform", Transform3D.IDENTITY)
            sum += Vector2(transform.origin.x, transform.origin.z)
        return sum / float(distribution.instances.size())

    var raw_objects: Dictionary = context.get("ir_objects", {})
    var raw_value: Variant = raw_objects.get(target)
    if typeof(raw_value) != TYPE_DICTIONARY or visiting.has(target):
        return world_bounds.get_center()

    visiting[target] = true
    var raw: Dictionary = raw_value
    var raw_kind := String(context.get("ir_kinds", {}).get(target, ""))
    if raw_kind == "network":
        var topology: Dictionary = raw.get("topology", {})
        var a := _semantic_token_center(String(topology.get("from", "center")), context, visiting)
        var b := _semantic_token_center(String(topology.get("to", "center")), context, visiting)
        visiting.erase(target)
        return (a + b) * 0.5

    var placement: Dictionary = raw.get("placement", {})
    if placement.has("anchor"):
        var anchored := anchor_point(String(placement.get("anchor", "center")))
        visiting.erase(target)
        return anchored

    var relations: Array = placement.get("relations", [])
    for rel in relations:
        var rel_kind := String(rel.get("type", ""))
        var rel_target := String(rel.get("target", ""))
        var target_point := _target_center(rel_target, context, visiting)
        if rel_kind == "inside" or rel_kind == "near" or rel_kind == "along":
            visiting.erase(target)
            return target_point
        if rel_kind == "direction_of":
            var axis := _direction_axis(String(rel.get("direction", "")))
            visiting.erase(target)
            return target_point + axis * 30.0
        if rel_kind == "far_from":
            var world_center := world_bounds.get_center()
            var away := (world_center - target_point).normalized()
            if away == Vector2.ZERO:
                away = Vector2(1.0, 0.0)
            visiting.erase(target)
            return target_point + away * FAR_THRESHOLD_M * 1.5

    visiting.erase(target)
    return world_bounds.get_center()

func _semantic_token_center(token: String, context: Dictionary, visiting: Dictionary) -> Vector2:
    if token in ["north", "south", "east", "west", "center", "northwest", "northeast", "southwest", "southeast", "whole"]:
        return anchor_point(token)
    return _target_center(token, context, visiting)

func _direction_matches(p: Vector2, c: Vector2, direction: String) -> bool:
    var delta := p - c
    match direction:
        "north": return delta.y < 0.0
        "south": return delta.y > 0.0
        "west": return delta.x < 0.0
        "east": return delta.x > 0.0
        "northwest": return delta.x < 0.0 and delta.y < 0.0
        "northeast": return delta.x > 0.0 and delta.y < 0.0
        "southwest": return delta.x < 0.0 and delta.y > 0.0
        "southeast": return delta.x > 0.0 and delta.y > 0.0
    return true

func _direction_axis(direction: String) -> Vector2:
    match direction:
        "north": return Vector2(0.0, -1.0)
        "south": return Vector2(0.0, 1.0)
        "west": return Vector2(-1.0, 0.0)
        "east": return Vector2(1.0, 0.0)
        "northwest": return Vector2(-1.0, -1.0).normalized()
        "northeast": return Vector2(1.0, -1.0).normalized()
        "southwest": return Vector2(-1.0, 1.0).normalized()
        "southeast": return Vector2(1.0, 1.0).normalized()
    return Vector2.ZERO

func _polyline_lengths(points: PackedVector3Array) -> Array[float]:
    var out: Array[float] = [0.0]
    for i in range(1, points.size()):
        var a := Vector2(points[i - 1].x, points[i - 1].z)
        var b := Vector2(points[i].x, points[i].z)
        out.append(out[-1] + a.distance_to(b))
    return out

func _sample_polyline(points: PackedVector3Array, lengths: Array[float], distance: float) -> Array:
    for i in range(1, lengths.size()):
        if distance <= lengths[i]:
            var span: float = lengths[i] - lengths[i - 1]
            var t := 0.0 if is_zero_approx(span) else (distance - lengths[i - 1]) / span
            var a := Vector2(points[i - 1].x, points[i - 1].z)
            var b := Vector2(points[i].x, points[i].z)
            return [a.lerp(b, t), (b - a).normalized()]
    var a := Vector2(points[-2].x, points[-2].z)
    var b := Vector2(points[-1].x, points[-1].z)
    return [b, (b - a).normalized()]
