class_name DistributionLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

const DENSITY_COUNTS := {"low": 24, "medium": 52, "high": 90}
const DENSITY_WEIGHTS := {"low": 0.20, "medium": 0.55, "high": 1.0}
const WEIGHTED_ATTEMPTS := 24

var binding_resolver = RuntimeBindingResolverScript.new()

func lower(
	item: Dictionary,
	catalog: PrototypeCatalog,
	solver: PlacementSolver,
	context: Dictionary,
	binding: Dictionary = {}
) -> ResolvedDistribution:
	var out := ResolvedDistribution.new()
	out.id = String(item.get("id", ""))
	out.semantic_type = String(item.get("type", ""))
	var prototype_id := catalog.choose_prototype(out.semantic_type)
	if prototype_id.is_empty():
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

	# Preserve the specialized road-side layout for the common no-gradient/no-binding case.
	# If a gradient or Runtime Binding exists, use general constrained weighted placement
	# so all semantic axes can participate together.
	if not along_target.is_empty() and density_profile.is_empty() and binding.is_empty():
		var network: ResolvedNetwork = context.get("networks", {}).get(along_target)
		var lateral := (network.width * 0.5 if network != null else 3.0) + radius + 3.0
		var points := solver.resolve_along(network, count, lateral, radius)
		for i in range(points.size()):
			out.instances.append(_instance(out.id, i, prototype_id, points[i], _yaw_toward_road(points[i], network, solver)))
		return out

	var arrangement := String(population.get("arrangement", {}).get("type", "random"))
	var domain: Rect2 = binding_resolver.resolve_domain(
		binding,
		context.get("spatial_payloads", {}),
		solver.world_bounds,
		Vector2(28.0, 28.0)
	)
	if not domain.has_area():
		domain = _domain_for_placement(placement, context, solver)

	if arrangement == "clustered":
		_place_clustered(out, prototype_id, count, radius, placement, context, solver, domain, density_profile)
	else:
		_place_scattered(
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
	return out

func _resolve_count(amount: Dictionary) -> int:
	if String(amount.get("mode", "density")) == "count":
		return maxi(0, int(amount.get("value", 0)))
	return int(DENSITY_COUNTS.get(String(amount.get("value", "medium")), 52))

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
) -> void:
	if count <= 0:
		return
	if uniform:
		_place_uniform(out, prototype_id, count, radius, placement, context, solver, domain, density_profile)
		return

	for i in range(count):
		var p := _weighted_candidate(placement, radius, context, solver, domain, density_profile)
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_id, p, solver.rng.randf_range(-PI, PI)))

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
) -> void:
	if density_profile.is_empty():
		var cols: int = maxi(1, int(ceil(sqrt(float(count)))))
		var rows: int = maxi(1, int(ceil(float(count) / float(cols))))
		var index := 0
		for r in range(rows):
			for c in range(cols):
				if index >= count:
					return
				var p := domain.position + Vector2(
					(float(c) + 0.5) / float(cols) * domain.size.x,
					(float(r) + 0.5) / float(rows) * domain.size.y
				)
				if solver.is_candidate_valid(p, placement, radius, context):
					solver.register_occupancy(p, radius, "%s:%03d" % [out.id, index])
					out.instances.append(_instance(out.id, index, prototype_id, p, solver.rng.randf_range(-PI, PI)))
					index += 1
		while index < count:
			var fallback := solver.resolve_candidate(placement, radius, context, domain)
			solver.register_occupancy(fallback, radius, "%s:%03d" % [out.id, index])
			out.instances.append(_instance(out.id, index, prototype_id, fallback, solver.rng.randf_range(-PI, PI)))
			index += 1
		return

	# A gradient and uniform arrangement are orthogonal in the IR. Generate a denser
	# regular candidate lattice, then choose a deterministic weighted subset. This
	# preserves spacing better than fully random rejection sampling while still
	# producing visibly different low/high density sides.
	var candidate_budget := maxi(count * 4, count + 8)
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
			var weight := _profile_weight(p, density_profile, domain, context, solver)
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
		var fallback := _weighted_candidate(placement, radius, context, solver, domain, density_profile)
		solver.register_occupancy(fallback, radius, "%s:%03d" % [out.id, index])
		out.instances.append(_instance(out.id, index, prototype_id, fallback, solver.rng.randf_range(-PI, PI)))
		index += 1

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
) -> void:
	if count <= 0:
		return
	var cluster_count := clampi(int(round(sqrt(float(count)) / 2.0)), 2, 6)
	var centers: Array[Vector2] = []
	for _i in range(cluster_count):
		centers.append(_weighted_candidate(placement, 0.0, context, solver, domain, density_profile))

	for i in range(count):
		var center := centers[i % centers.size()]
		var p := center + Vector2.from_angle(solver.rng.randf_range(0.0, TAU)) * solver.rng.randf_range(2.0, 13.0)
		var weight := _profile_weight(p, density_profile, domain, context, solver)
		var accepted := (
			domain.has_point(p)
			and solver.is_candidate_valid(p, placement, radius, context)
			and solver.rng.randf() <= weight
		)
		if not accepted:
			p = _weighted_candidate(placement, radius, context, solver, domain, density_profile)
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_id, p, solver.rng.randf_range(-PI, PI)))

func _weighted_candidate(
	placement: Dictionary,
	radius: float,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	density_profile: Dictionary
) -> Vector2:
	if density_profile.is_empty():
		return solver.resolve_candidate(placement, radius, context, domain)
	var best := domain.get_center()
	var best_weight := -1.0
	for _attempt in range(WEIGHTED_ATTEMPTS):
		var candidate := solver.resolve_candidate(placement, radius, context, domain)
		var weight := _profile_weight(candidate, density_profile, domain, context, solver)
		if weight > best_weight:
			best = candidate
			best_weight = weight
		if solver.rng.randf() <= weight:
			return candidate
	return best

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
	var from_affinity := _selector_affinity(p, from_selector, domain, context, solver)
	var to_affinity := _selector_affinity(p, to_selector, domain, context, solver)
	var denominator := from_affinity + to_affinity
	var t := 0.5 if denominator <= 0.0001 else to_affinity / denominator
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

func _domain_for_placement(placement: Dictionary, context: Dictionary, solver: PlacementSolver) -> Rect2:
	for rel in placement.get("relations", []):
		if String(rel.get("type", "")) == "inside":
			var region: ResolvedRegion = context.get("regions", {}).get(String(rel.get("target", "")))
			if region != null:
				return solver.polygon_aabb(region.polygon)
	return solver.anchor_rect(String(placement.get("anchor", "whole")))

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
