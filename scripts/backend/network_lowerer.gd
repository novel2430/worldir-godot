class_name NetworkLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")
const SUPPORTED_PLACEMENT_RELATIONS := ["inside", "near", "far_from", "direction_of"]

var binding_resolver = RuntimeBindingResolverScript.new()
var last_error := ""

func lower(
	item: Dictionary,
	solver: PlacementSolver,
	seed_value: int,
	context: Dictionary,
	binding: Dictionary = {}
) -> ResolvedNetwork:
	last_error = ""
	var out := ResolvedNetwork.new()
	out.id = String(item.get("id", ""))
	out.semantic_type = String(item.get("type", "road"))
	out.width = 5.5 if out.semantic_type == "road" else 2.5
	out.surface_kind = out.semantic_type

	var placement: Dictionary = item.get("placement", {})
	var placement_relations: Array = placement.get("relations", [])
	for rel in placement_relations:
		var kind: String = String(rel.get("type", ""))
		if not (kind in SUPPORTED_PLACEMENT_RELATIONS):
			last_error = "Backend capability missing: Network '%s' placement relation '%s' is not implemented" % [out.id, kind]
			return null

	var topology: Dictionary = item.get("topology", {})
	var from_token: String = String(topology.get("from", "south"))
	var to_token: String = String(topology.get("to", "north"))
	var start: Vector2 = _topology_point(from_token, solver, context)
	var finish: Vector2 = _topology_point(to_token, solver, context)
	var via: Array = topology.get("via", [])

	# Topology owns connection endpoints and via order. Placement constrains the
	# body of the path. In particular, world-anchor endpoints remain untouched:
	# south -> north + inside town means a world-spanning road routed through town,
	# not a road whose endpoints are clamped into the town polygon.
	var has_world_anchor_endpoint: bool = _is_world_anchor(from_token) or _is_world_anchor(to_token)
	var traversal_points: Array[Vector2] = []
	var placement_anchor: String = String(placement.get("anchor", ""))
	if not placement_anchor.is_empty() and placement_anchor != "whole":
		traversal_points.append(solver.anchor_point(placement_anchor))
	for rel in placement_relations:
		var traversal_result := _relation_traversal_point(rel, solver, context)
		if not bool(traversal_result.get("ok", false)):
			last_error = "Placement failed for Network '%s': %s" % [out.id, String(traversal_result.get("error", "invalid placement relation"))]
			return null
		_append_control_point_if_distinct(traversal_points, traversal_result["point"])

	var semantic_constrained: bool = placement.has("anchor") or not placement_relations.is_empty()
	var has_strict_domain_constraint: bool = (
		(not placement_anchor.is_empty() and placement_anchor != "whole")
		or _has_relation(placement_relations, "inside")
	)
	var semantic_domain: Rect2 = Rect2()
	if has_strict_domain_constraint and not has_world_anchor_endpoint:
		semantic_domain = solver.placement_domain(placement, context)
		if not semantic_domain.has_area():
			last_error = "Placement failed for Network '%s': placement constraints have no spatial domain" % out.id
			return null

	var binding_domain: Rect2 = binding_resolver.resolve_domain(
		binding,
		context.get("spatial_payloads", {}),
		solver.world_bounds,
		Vector2(24.0, 24.0)
	)
	var binding_mode: String = String(binding.get("placement", "at"))

	var constrained_domain: Rect2 = semantic_domain
	if binding_domain.has_area() and binding_mode == "inside" and not has_world_anchor_endpoint:
		constrained_domain = binding_domain if not constrained_domain.has_area() else solver.intersect_rect(constrained_domain, binding_domain)
		if not constrained_domain.has_area():
			last_error = "Placement failed for Network '%s': Runtime Binding conflicts with IR placement" % out.id
			return null

	var control: Array[Vector2] = []
	if constrained_domain.has_area():
		var constrained_points: Array[Vector2] = _inside_binding_points(start, finish, constrained_domain)
		control.append(constrained_points[0])
		for token in via:
			var via_point: Vector2 = _topology_point(String(token), solver, context)
			_append_control_point_if_distinct(control, _clamp_point(via_point, constrained_domain))
		for traversal_point in traversal_points:
			_append_control_point_if_distinct(control, _clamp_point(traversal_point, constrained_domain))
		_append_control_point_if_distinct(control, constrained_points[1])
	else:
		control.append(start)
		for token in via:
			_append_control_point_if_distinct(control, _topology_point(String(token), solver, context))
		for traversal_point in traversal_points:
			_append_control_point_if_distinct(control, traversal_point)
		if binding_domain.has_area():
			var center: Vector2 = binding_domain.get_center()
			if not has_world_anchor_endpoint and semantic_constrained and semantic_domain.has_area() and not semantic_domain.has_point(center):
				last_error = "Placement failed for Network '%s': Runtime Binding target violates IR placement" % out.id
				return null
			_append_control_point_if_distinct(control, center)
		_append_control_point_if_distinct(control, finish)

	var local_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	local_rng.seed = seed_value ^ out.id.hash()
	var points: PackedVector3Array = PackedVector3Array()
	for seg in range(control.size() - 1):
		var a: Vector2 = control[seg]
		var b: Vector2 = control[seg + 1]
		var tangent: Vector2 = (b - a).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		var steps: int = 7
		for i in range(steps):
			if seg > 0 and i == 0:
				continue
			var t: float = float(i) / float(steps - 1)
			var bend: float = sin(t * PI) * local_rng.randf_range(-5.0, 5.0)
			var p: Vector2 = a.lerp(b, t) + normal * bend
			if constrained_domain.has_area():
				p = _clamp_point(p, constrained_domain)
			points.append(Vector3(p.x, 0.08, p.y))
	out.curve_points = points
	return out

func _topology_point(token: String, solver: PlacementSolver, context: Dictionary) -> Vector2:
	if _is_world_anchor(token):
		return solver.anchor_point(token)
	return solver.target_center(token, context)

func _is_world_anchor(token: String) -> bool:
	return token in [
		"north",
		"south",
		"east",
		"west",
		"center",
		"northwest",
		"northeast",
		"southwest",
		"southeast",
		"whole",
	]

func _region_traversal_point(region: ResolvedRegion, solver: PlacementSolver) -> Vector2:
	var rect: Rect2 = solver.polygon_aabb(region.polygon)
	var center: Vector2 = rect.get_center()
	if Geometry2D.is_point_in_polygon(center, region.polygon):
		return center

	# Region V0.5 polygons are mild irregularizations of a base domain, so their
	# AABB center should normally be inside. Keep a deterministic grid fallback
	# for future concave shapes without consuming PlacementSolver RNG state.
	for y_index in range(1, 5):
		for x_index in range(1, 5):
			var x_t: float = float(x_index) / 5.0
			var y_t: float = float(y_index) / 5.0
			var candidate: Vector2 = Vector2(
				lerpf(rect.position.x, rect.end.x, x_t),
				lerpf(rect.position.y, rect.end.y, y_t)
			)
			if Geometry2D.is_point_in_polygon(candidate, region.polygon):
				return candidate
	return center

func _relation_traversal_point(relation: Dictionary, solver: PlacementSolver, context: Dictionary) -> Dictionary:
	var kind := String(relation.get("type", ""))
	var target := String(relation.get("target", ""))
	if kind == "inside":
		var region: ResolvedRegion = context.get("regions", {}).get(target)
		if region == null:
			return {"ok": false, "error": "inside target '%s' has not been resolved" % target}
		return {"ok": true, "point": _region_traversal_point(region, solver)}
	if kind == "near":
		return {"ok": true, "point": solver.target_center(target, context)}
	if kind == "far_from":
		return {"ok": true, "point": _farthest_anchor_from(target, solver, context)}
	if kind == "direction_of":
		var center := solver.target_center(target, context)
		var axis := _direction_axis(String(relation.get("direction", "")))
		var point := center + axis * (PlacementSolver.FAR_THRESHOLD_M + 4.0)
		return {"ok": true, "point": _clamp_point(point, solver.world_bounds)}
	return {"ok": false, "error": "relation '%s' is not implemented" % kind}

func _farthest_anchor_from(target: String, solver: PlacementSolver, context: Dictionary) -> Vector2:
	var bounds := solver.world_bounds
	var inset := Vector2(0.001, 0.001)
	var candidates: Array[Vector2] = [
		bounds.position + inset,
		Vector2(bounds.end.x - inset.x, bounds.position.y + inset.y),
		Vector2(bounds.position.x + inset.x, bounds.end.y - inset.y),
		bounds.end - inset,
	]
	var best := candidates[0]
	var best_distance := -1.0
	for candidate in candidates:
		var distance := solver.distance_to_target(candidate, target, context)
		if distance > best_distance:
			best = candidate
			best_distance = distance
	return best

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

func _has_relation(relations: Array, kind: String) -> bool:
	for relation in relations:
		if String(relation.get("type", "")) == kind:
			return true
	return false

func _append_control_point_if_distinct(control: Array[Vector2], point: Vector2) -> void:
	if not control.is_empty() and control[control.size() - 1].is_equal_approx(point):
		return
	control.append(point)

func _inside_binding_points(start: Vector2, finish: Vector2, domain: Rect2) -> Array[Vector2]:
	var direction: Vector2 = finish - start
	var points: Array[Vector2] = []
	if absf(direction.x) >= absf(direction.y):
		var left: Vector2 = Vector2(domain.position.x + domain.size.x * 0.15, domain.get_center().y)
		var right: Vector2 = Vector2(domain.end.x - domain.size.x * 0.15, domain.get_center().y)
		if direction.x >= 0.0:
			points.append(left)
			points.append(right)
		else:
			points.append(right)
			points.append(left)
		return points
	var top: Vector2 = Vector2(domain.get_center().x, domain.position.y + domain.size.y * 0.15)
	var bottom: Vector2 = Vector2(domain.get_center().x, domain.end.y - domain.size.y * 0.15)
	if direction.y >= 0.0:
		points.append(top)
		points.append(bottom)
	else:
		points.append(bottom)
		points.append(top)
	return points

func _clamp_point(point: Vector2, domain: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, domain.position.x, domain.end.x),
		clampf(point.y, domain.position.y, domain.end.y)
	)
