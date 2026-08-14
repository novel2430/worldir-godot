class_name DistributionLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

const DENSITY_COUNTS := {"low": 24, "medium": 52, "high": 90}
const UNSPECIFIED_COUNT := 12
const DENSITY_WEIGHTS := {"low": 0.20, "medium": 0.55, "high": 1.0}
const WEIGHTED_ATTEMPTS := 24

var binding_resolver = RuntimeBindingResolverScript.new()
var last_error := ""

func lower(
	item: Dictionary,
	catalog: PrototypeCatalog,
	solver: PlacementSolver,
	context: Dictionary,
	binding: Dictionary = {}
) -> ResolvedDistribution:
	last_error = ""
	var out := ResolvedDistribution.new()
	out.id = String(item.get("id", ""))
	out.semantic_type = String(item.get("type", ""))
	var prototype_id := catalog.choose_prototype(out.semantic_type)
	if prototype_id.is_empty():
		last_error = "Backend capability missing: no TSCN prototype for Distribution '%s' (type='%s')" % [out.id, out.semantic_type]
		return null

	var meta := catalog.get_metadata(prototype_id)
	var radius := float(meta.get("placement_radius", 1.0)) + float(meta.get("clearance", 0.0))
	var population: Dictionary = item.get("population", {})
	var amount: Dictionary = population.get("amount", {})
	var count := _resolve_count(amount)
	var density_profile: Dictionary = population.get("density_profile", {})
	var placement: Dictionary = item.get("placement", {})
	var relations: Array = placement.get("relations", [])
	var along_target := _relation_target(relations, "along")

	var binding_domain: Rect2 = binding_resolver.resolve_domain(
		binding,
		context.get("spatial_payloads", {}),
		solver.world_bounds,
		Vector2(28.0, 28.0)
	)
	var domain: Rect2 = solver.placement_domain(placement, context, binding_domain)
	if not domain.has_area():
		last_error = "Placement failed for Distribution '%s': placement constraints have no overlapping spatial domain" % out.id
		return null

	# Keep the road-side realization because it looks much better than random rejection,
	# but validate EVERY placement relation (inside/far_from/etc.) for every instance.
	if not along_target.is_empty() and density_profile.is_empty() and binding.is_empty():
		var network: ResolvedNetwork = context.get("networks", {}).get(along_target)
		if network == null:
			last_error = "Placement failed for Distribution '%s': along target '%s' is not resolved" % [out.id, along_target]
			return null
		var lateral := network.width * 0.5 + radius + 1.0
		if not _place_along_constrained(out, prototype_id, count, radius, placement, context, solver, domain, network, lateral):
			return null
		return out

	var arrangement := String(population.get("arrangement", {}).get("type", "random"))
	var ok: bool = true
	if arrangement == "clustered":
		ok = _place_clustered(out, prototype_id, count, radius, placement, context, solver, domain, density_profile)
	else:
		ok = _place_scattered(
			out,
			prototype_id,
			count,
			radius,
			placement,
			context,
			solver,
			domain,
			arrangement == "uniform",
			density_profile
		)
	if not ok:
		return null
	return out

func _resolve_count(amount: Dictionary) -> int:
	# Missing population amount is unspecified in World IR V2. It is NOT semantic
	# medium density. Use a small backend realization default instead.
	if amount.is_empty():
		return UNSPECIFIED_COUNT
	if String(amount.get("mode", "")) == "count":
		return maxi(0, int(amount.get("value", 0)))
	return int(DENSITY_COUNTS.get(String(amount.get("value", "medium")), DENSITY_COUNTS["medium"]))

func _place_along_constrained(
	out: ResolvedDistribution,
	prototype_id: String,
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	network: ResolvedNetwork,
	lateral_offset: float
) -> bool:
	if count <= 0:
		return true
	if network.curve_points.size() < 2:
		last_error = "Placement failed for Distribution '%s': along target has no usable curve" % out.id
		return false

	# Build a dense deterministic pool along both road sides. This lets another
	# conjunctive relation (inside/far_from/direction_of) filter candidates instead
	# of being discarded by the specialized along path.
	var candidate_budget: int = maxi(96, count * 12)
	var candidates: Array[Vector2] = []
	for j in range(candidate_budget):
		var t: float = (float(j) + 0.5) / float(candidate_budget)
		var sample: Array = solver.sample_network(network, t)
		var road_point: Vector2 = sample[0]
		var tangent: Vector2 = sample[1]
		var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
		for side in [-1.0, 1.0]:
			var side_value: float = float(side)
			var p: Vector2 = road_point + normal * lateral_offset * side_value
			if domain.has_point(p) and solver.is_semantically_valid(p, placement, context):
				candidates.append(p)

	if candidates.size() < count:
		last_error = "Placement failed for Distribution '%s': only %d along-road candidates satisfy all IR relations, need %d" % [out.id, candidates.size(), count]
		return false

	var used: Dictionary = {}
	for i in range(count):
		var desired_index: int = clampi(int(floor((float(i) + 0.5) * float(candidates.size()) / float(count))), 0, candidates.size() - 1)
		var chosen_index: int = _nearest_usable_candidate(candidates, desired_index, used, radius, solver)
		if chosen_index < 0:
			# Geometry occupancy is currently best-effort for repeated roadside objects;
			# semantic relations remain hard constraints. Fall back only to another
			# semantically valid, unused point rather than an arbitrary invalid point.
			chosen_index = _nearest_unused_candidate(candidates, desired_index, used)
		if chosen_index < 0:
			last_error = "Placement failed for Distribution '%s': insufficient unique along-road candidates" % out.id
			return false
		used[chosen_index] = true
		var p: Vector2 = candidates[chosen_index]
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_id, p, _yaw_toward_road(p, network, solver)))
	return true

func _nearest_usable_candidate(candidates: Array[Vector2], desired: int, used: Dictionary, radius: float, solver: PlacementSolver) -> int:
	for delta in range(candidates.size()):
		for index in [desired - delta, desired + delta]:
			if index < 0 or index >= candidates.size() or used.has(index):
				continue
			if not solver.overlaps(candidates[index], radius):
				return index
	return -1

func _nearest_unused_candidate(candidates: Array[Vector2], desired: int, used: Dictionary) -> int:
	for delta in range(candidates.size()):
		for index in [desired - delta, desired + delta]:
			if index >= 0 and index < candidates.size() and not used.has(index):
				return index
	return -1

func _place_scattered(
	out: ResolvedDistribution,
	prototype_id: String,
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	uniform: bool,
	density_profile: Dictionary
) -> bool:
	if count <= 0:
		return true
	if uniform:
		return _place_uniform(out, prototype_id, count, radius, placement, context, solver, domain, density_profile)

	for i in range(count):
		var candidate: Dictionary = _weighted_candidate(placement, radius, context, solver, domain, density_profile)
		if not bool(candidate.get("ok", false)):
			last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, i, String(candidate.get("error", "unknown placement failure"))]
			return false
		var p: Vector2 = candidate["position"]
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_id, p, solver.rng.randf_range(-PI, PI)))
	return true

func _place_uniform(
	out: ResolvedDistribution,
	prototype_id: String,
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	density_profile: Dictionary
) -> bool:
	if density_profile.is_empty():
		var cols: int = maxi(1, int(ceil(sqrt(float(count)))))
		var rows: int = maxi(1, int(ceil(float(count) / float(cols))))
		var index := 0
		for r in range(rows):
			for c in range(cols):
				if index >= count:
					return true
				var p := domain.position + Vector2(
					(float(c) + 0.5) / float(cols) * domain.size.x,
					(float(r) + 0.5) / float(rows) * domain.size.y
				)
				if solver.is_candidate_valid(p, placement, radius, context):
					solver.register_occupancy(p, radius, "%s:%03d" % [out.id, index])
					out.instances.append(_instance(out.id, index, prototype_id, p, solver.rng.randf_range(-PI, PI)))
					index += 1
		while index < count:
			var candidate: Dictionary = solver.try_resolve_candidate(placement, radius, context, domain)
			if not bool(candidate.get("ok", false)):
				last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, index, String(candidate.get("error", "unknown placement failure"))]
				return false
			var fallback: Vector2 = candidate["position"]
			solver.register_occupancy(fallback, radius, "%s:%03d" % [out.id, index])
			out.instances.append(_instance(out.id, index, prototype_id, fallback, solver.rng.randf_range(-PI, PI)))
			index += 1
		return true

	var candidate_budget: int = maxi(count * 4, count + 8)
	var cols: int = maxi(1, int(ceil(sqrt(float(candidate_budget)))))
	var rows: int = maxi(1, int(ceil(float(candidate_budget) / float(cols))))
	var candidates: Array = []
	for r in range(rows):
		for c in range(cols):
			var p := domain.position + Vector2(
				(float(c) + 0.5) / float(cols) * domain.size.x,
				(float(r) + 0.5) / float(rows) * domain.size.y
			)
			if not solver.is_candidate_valid(p, placement, radius, context):
				continue
			var weight: float = _profile_weight(p, density_profile, domain, context, solver)
			candidates.append({"position": p, "rank": solver.rng.randf() * weight})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rank"]) > float(b["rank"]))

	var index := 0
	for candidate in candidates:
		if index >= count:
			break
		var p: Vector2 = candidate["position"]
		if solver.overlaps(p, radius):
			continue
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, index])
		out.instances.append(_instance(out.id, index, prototype_id, p, solver.rng.randf_range(-PI, PI)))
		index += 1

	while index < count:
		var fallback_result := _weighted_candidate(placement, radius, context, solver, domain, density_profile)
		if not bool(fallback_result.get("ok", false)):
			last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, index, String(fallback_result.get("error", "unknown placement failure"))]
			return false
		var fallback: Vector2 = fallback_result["position"]
		solver.register_occupancy(fallback, radius, "%s:%03d" % [out.id, index])
		out.instances.append(_instance(out.id, index, prototype_id, fallback, solver.rng.randf_range(-PI, PI)))
		index += 1
	return true

func _place_clustered(
	out: ResolvedDistribution,
	prototype_id: String,
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	density_profile: Dictionary
) -> bool:
	if count <= 0:
		return true
	var cluster_count := clampi(int(round(sqrt(float(count)) / 2.0)), 2, 6)
	var centers: Array[Vector2] = []
	for _i in range(cluster_count):
		var center_result: Dictionary = _weighted_candidate(placement, 0.0, context, solver, domain, density_profile)
		if not bool(center_result.get("ok", false)):
			last_error = "Placement failed for Distribution '%s' cluster center: %s" % [out.id, String(center_result.get("error", "unknown placement failure"))]
			return false
		centers.append(center_result["position"])

	for i in range(count):
		var center: Vector2 = centers[i % centers.size()]
		var p: Vector2 = center + Vector2.from_angle(solver.rng.randf_range(0.0, TAU)) * solver.rng.randf_range(2.0, 13.0)
		var weight: float = _profile_weight(p, density_profile, domain, context, solver)
		var accepted: bool = (
			domain.has_point(p)
			and solver.is_candidate_valid(p, placement, radius, context)
			and solver.rng.randf() <= weight
		)
		if not accepted:
			var candidate: Dictionary = _weighted_candidate(placement, radius, context, solver, domain, density_profile)
			if not bool(candidate.get("ok", false)):
				last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, i, String(candidate.get("error", "unknown placement failure"))]
				return false
			p = candidate["position"]
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_id, p, solver.rng.randf_range(-PI, PI)))
	return true

func _weighted_candidate(
	placement: Dictionary,
	radius: float,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	density_profile: Dictionary
) -> Dictionary:
	if density_profile.is_empty():
		return solver.try_resolve_candidate(placement, radius, context, domain)

	var best_position: Vector2 = Vector2.ZERO
	var best_weight: float = -1.0
	var found: bool = false
	for _attempt in range(WEIGHTED_ATTEMPTS):
		var result: Dictionary = solver.try_resolve_candidate(placement, radius, context, domain)
		if not bool(result.get("ok", false)):
			continue
		var candidate: Vector2 = result["position"]
		var weight: float = _profile_weight(candidate, density_profile, domain, context, solver)
		if weight > best_weight:
			best_position = candidate
			best_weight = weight
			found = true
		if solver.rng.randf() <= weight:
			return {"ok": true, "position": candidate}
	if found:
		return {"ok": true, "position": best_position}
	return {"ok": false, "error": "No valid weighted candidate satisfies placement constraints"}

func _profile_weight(
	p: Vector2,
	profile: Dictionary,
	domain: Rect2,
	context: Dictionary,
	solver: PlacementSolver
) -> float:
	if profile.is_empty():
		return 1.0
	var from_endpoint: Dictionary = profile.get("from", {})
	var to_endpoint: Dictionary = profile.get("to", {})
	var from_selector: Dictionary = from_endpoint.get("selector", {})
	var to_selector: Dictionary = to_endpoint.get("selector", {})
	var from_affinity: float = _selector_affinity(p, from_selector, domain, context, solver)
	var to_affinity: float = _selector_affinity(p, to_selector, domain, context, solver)
	var denominator: float = from_affinity + to_affinity
	var t: float = 0.5 if denominator <= 0.0001 else to_affinity / denominator
	var from_density := float(DENSITY_WEIGHTS.get(String(from_endpoint.get("density", "medium")), 0.55))
	var to_density := float(DENSITY_WEIGHTS.get(String(to_endpoint.get("density", "medium")), 0.55))
	return clampf(lerpf(from_density, to_density, t), 0.05, 1.0)

func _selector_affinity(
	p: Vector2,
	selector: Dictionary,
	domain: Rect2,
	context: Dictionary,
	solver: PlacementSolver
) -> float:
	var kind := String(selector.get("type", ""))
	var scale := maxf(1.0, domain.size.length())
	match kind:
		"anchor":
			var anchor := String(selector.get("value", "center"))
			if anchor == "whole":
				return 1.0
			var target := _domain_anchor_point(domain, anchor)
			return clampf(1.0 - p.distance_to(target) / scale, 0.0, 1.0)
		"near":
			var near_distance := solver.distance_to_target(p, String(selector.get("target", "")), context)
			return clampf(1.0 - near_distance / scale, 0.0, 1.0)
		"far_from":
			var far_distance := solver.distance_to_target(p, String(selector.get("target", "")), context)
			return clampf(far_distance / scale, 0.0, 1.0)
		"direction_of":
			return solver.direction_affinity(
				p,
				String(selector.get("target", "")),
				String(selector.get("direction", "")),
				context,
				scale
			)
	return 0.5

func _domain_anchor_point(domain: Rect2, anchor: String) -> Vector2:
	var center := domain.get_center()
	match anchor:
		"north": return Vector2(center.x, domain.position.y)
		"south": return Vector2(center.x, domain.end.y)
		"west": return Vector2(domain.position.x, center.y)
		"east": return Vector2(domain.end.x, center.y)
		"northwest": return domain.position
		"northeast": return Vector2(domain.end.x, domain.position.y)
		"southwest": return Vector2(domain.position.x, domain.end.y)
		"southeast": return domain.end
		"center", "whole": return center
	return center

func _relation_target(relations: Array, kind: String) -> String:
	for rel in relations:
		if String(rel.get("type", "")) == kind:
			return String(rel.get("target", ""))
	return ""

func _yaw_toward_road(p: Vector2, network: ResolvedNetwork, solver: PlacementSolver) -> float:
	if network == null:
		return solver.rng.randf_range(-PI, PI)
	var q := solver.nearest_point_on_network(p, network)
	var direction := q - p
	return atan2(direction.x, direction.y)

func _instance(distribution_id: String, index: int, prototype_id: String, p: Vector2, yaw: float) -> Dictionary:
	return {
		"id": "%s:%03d" % [distribution_id, index],
		"prototype_id": prototype_id,
		"transform": Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y)),
	}
