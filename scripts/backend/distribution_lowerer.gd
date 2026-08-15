class_name DistributionLowerer
extends RefCounted

const RuntimeBindingResolverScript = preload("res://scripts/backend/runtime_binding_resolver.gd")

const DEFAULT_POPULATION_BUDGET := 12
const USABLE_AREA_GRID_SIZE := 36
const RANDOM_PACKING_LOSS := 1.2
const DENSITY_SPACING_MULTIPLIERS := {"low": 1.6, "medium": 1.0, "high": 0.45}
const POPULATION_CAPS := {"tree": 200, "house": 60, "tombstone": 150, "lamp": 100}
const DEFAULT_POPULATION_CAP := 100
const DENSITY_WEIGHTS := {"low": 0.20, "medium": 0.55, "high": 1.0}
const WEIGHTED_ATTEMPTS := 24
const FOREST_CLUSTER_COUNT := 3
const FOREST_EDGE_DENSITY := 0.12
const FOREST_INTERIOR_DEPTH_RATIO := 0.14
const FOREST_CLUSTER_RADIUS_RATIO := 0.22

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
	var candidate_prototype_ids := catalog.get_prototype_ids(out.semantic_type)
	if candidate_prototype_ids.is_empty():
		last_error = "Backend capability missing: no TSCN prototype for Distribution '%s' (type='%s')" % [out.id, out.semantic_type]
		return null

	var meta := _combined_population_metadata(catalog, candidate_prototype_ids)
	var radius := float(meta.get(
		"population_occupancy_radius",
		float(meta.get("placement_radius", 1.0)) + float(meta.get("clearance", 0.0))
	))
	var visual_footprint: Vector2 = meta.get("population_footprint", Vector2.ONE * radius * 2.0)
	var visual_radius := visual_footprint.length() * 0.5
	var population: Dictionary = item.get("population", {})
	var amount: Dictionary = population.get("amount", {})
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
	var count := _resolve_count(amount, out.semantic_type, meta, radius, placement, context, solver, domain)
	if count < 0:
		last_error = "Placement failed for Distribution '%s': density placement has no usable area" % out.id
		return null
	var variants := _choose_instance_variants(catalog, out.semantic_type, count, solver.rng)
	var instance_prototype_ids: Array[String] = variants["prototype_ids"]
	var instance_scales: Array[float] = variants["scales"]

	# Keep the road-side realization because it looks much better than random rejection,
	# but validate EVERY placement relation (inside/far_from/etc.) for every instance.
	if not along_target.is_empty() and density_profile.is_empty() and binding.is_empty():
		var network: ResolvedNetwork = context.get("networks", {}).get(along_target)
		if network == null:
			last_error = "Placement failed for Distribution '%s': along target '%s' is not resolved" % [out.id, along_target]
			return null
		var roadside_extent := minf(visual_footprint.x, visual_footprint.y) * 0.5
		var lateral := network.width * 0.5 + maxf(radius, roadside_extent) + float(meta.get("roadside_setback", 1.0))
		var yaw_jitter := deg_to_rad(float(meta.get("roadside_yaw_jitter_degrees", 0.0)))
		if not _place_along_constrained(out, instance_prototype_ids, instance_scales, count, radius, placement, context, solver, domain, network, lateral, yaw_jitter):
			return null
		return out

	var arrangement := String(population.get("arrangement", {}).get("type", "random"))
	# A forest is visually read through a sparse edge and denser interior groups.
	# This is a backend realization policy for an explicit tree Distribution, not
	# semantic completion: it creates no objects and never mutates the World IR.
	# Explicit gradient and uniform arrangements remain authoritative.
	var realization_profile: Dictionary = {}
	if density_profile.is_empty() and arrangement != "uniform":
		realization_profile = _forest_realization_profile(out, placement, context, domain)
	var ok: bool = true
	if arrangement == "clustered":
		ok = _place_clustered(out, instance_prototype_ids, instance_scales, count, radius, placement, context, solver, domain, density_profile, realization_profile)
	else:
		ok = _place_scattered(
			out,
			instance_prototype_ids,
			instance_scales,
			count,
			radius,
			placement,
			context,
			solver,
			domain,
			arrangement == "uniform",
			density_profile,
			realization_profile
		)
	if not ok:
		return null
	return out

func _combined_population_metadata(catalog: PrototypeCatalog, prototype_ids: Array[String]) -> Dictionary:
	var combined := catalog.get_metadata(prototype_ids[0]).duplicate()
	var footprint := Vector2.ZERO
	var occupancy_radius := 0.0
	var spacing := 0.0
	var roadside_setback := 0.0
	var roadside_yaw_jitter_degrees := 0.0
	for prototype_id in prototype_ids:
		var meta := catalog.get_metadata(prototype_id)
		var candidate_footprint: Vector2 = meta.get("population_footprint", Vector2.ZERO)
		footprint.x = maxf(footprint.x, candidate_footprint.x)
		footprint.y = maxf(footprint.y, candidate_footprint.y)
		occupancy_radius = maxf(occupancy_radius, float(meta.get("population_occupancy_radius", 0.0)))
		spacing = maxf(spacing, float(meta.get("population_spacing", 0.0)))
		roadside_setback = maxf(roadside_setback, float(meta.get("roadside_setback", 0.0)))
		roadside_yaw_jitter_degrees = maxf(roadside_yaw_jitter_degrees, float(meta.get("roadside_yaw_jitter_degrees", 0.0)))
	combined["population_footprint"] = footprint
	combined["population_occupancy_radius"] = occupancy_radius
	combined["population_spacing"] = spacing
	combined["roadside_setback"] = roadside_setback
	combined["roadside_yaw_jitter_degrees"] = roadside_yaw_jitter_degrees
	return combined

func _choose_instance_variants(
	catalog: PrototypeCatalog,
	semantic_type: String,
	count: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var prototype_ids: Array[String] = []
	var scales: Array[float] = []
	var options := catalog.get_prototype_ids(semantic_type)
	for _index in range(count):
		var variant := catalog.choose_population_variant(options, rng)
		prototype_ids.append(String(variant.get("prototype_id", "")))
		scales.append(float(variant.get("scale", 1.0)))
	return {"prototype_ids": prototype_ids, "scales": scales}

func _resolve_count(
	amount: Dictionary,
	semantic_type: String,
	prototype_meta: Dictionary,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2
) -> int:
	# Missing population amount is unspecified in World IR V2. It is NOT semantic
	# medium density. Use a small backend realization default instead.
	if amount.is_empty():
		return DEFAULT_POPULATION_BUDGET
	if String(amount.get("mode", "")) == "count":
		return maxi(0, int(amount.get("value", 0)))

	var density := String(amount.get("value", "medium"))
	var usable_area := _estimate_usable_area(domain, placement, radius, context, solver)
	if usable_area <= 0.0:
		return -1
	var footprint: Vector2 = prototype_meta.get("population_footprint", Vector2.ONE * radius * 2.0)
	var preferred_spacing := float(prototype_meta.get("population_spacing", 2.0))
	var spacing_multiplier := float(DENSITY_SPACING_MULTIPLIERS.get(
		density,
		DENSITY_SPACING_MULTIPLIERS["medium"]
	))
	var spacing := preferred_spacing * spacing_multiplier
	var area_per_instance := (
		maxf(0.1, footprint.x + spacing)
		* maxf(0.1, footprint.y + spacing)
		* RANDOM_PACKING_LOSS
	)
	var population_cap := int(POPULATION_CAPS.get(semantic_type, DEFAULT_POPULATION_CAP))
	return clampi(int(round(usable_area / area_per_instance)), 1, population_cap)

func _estimate_usable_area(
	domain: Rect2,
	placement: Dictionary,
	radius: float,
	context: Dictionary,
	solver: PlacementSolver
) -> float:
	if not domain.has_area():
		return 0.0
	var valid_samples := 0
	var total_samples := USABLE_AREA_GRID_SIZE * USABLE_AREA_GRID_SIZE
	for row in range(USABLE_AREA_GRID_SIZE):
		for column in range(USABLE_AREA_GRID_SIZE):
			var point := domain.position + Vector2(
				(float(column) + 0.5) / float(USABLE_AREA_GRID_SIZE) * domain.size.x,
				(float(row) + 0.5) / float(USABLE_AREA_GRID_SIZE) * domain.size.y
			)
			if solver.is_candidate_valid(point, placement, radius, context):
				valid_samples += 1
	return domain.get_area() * float(valid_samples) / float(total_samples)

func _place_along_constrained(
	out: ResolvedDistribution,
	prototype_ids: Array[String],
	instance_scales: Array[float],
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	network: ResolvedNetwork,
	lateral_offset: float,
	yaw_jitter: float
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
		var yaw := _yaw_toward_road(p, network, solver) + solver.rng.randf_range(-yaw_jitter, yaw_jitter)
		out.instances.append(_instance(out.id, i, prototype_ids[i], instance_scales[i], p, yaw))
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
	prototype_ids: Array[String],
	instance_scales: Array[float],
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	uniform: bool,
	density_profile: Dictionary,
	realization_profile: Dictionary
) -> bool:
	if count <= 0:
		return true
	if uniform:
		return _place_uniform(out, prototype_ids, instance_scales, count, radius, placement, context, solver, domain, density_profile)

	for i in range(count):
		var candidate: Dictionary = _weighted_candidate(placement, radius, context, solver, domain, density_profile, realization_profile)
		if not bool(candidate.get("ok", false)):
			last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, i, String(candidate.get("error", "unknown placement failure"))]
			return false
		var p: Vector2 = candidate["position"]
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_ids[i], instance_scales[i], p, solver.rng.randf_range(-PI, PI)))
	return true

func _place_uniform(
	out: ResolvedDistribution,
	prototype_ids: Array[String],
	instance_scales: Array[float],
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
					out.instances.append(_instance(out.id, index, prototype_ids[index], instance_scales[index], p, solver.rng.randf_range(-PI, PI)))
					index += 1
		while index < count:
			var candidate: Dictionary = solver.try_resolve_candidate(placement, radius, context, domain)
			if not bool(candidate.get("ok", false)):
				last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, index, String(candidate.get("error", "unknown placement failure"))]
				return false
			var fallback: Vector2 = candidate["position"]
			solver.register_occupancy(fallback, radius, "%s:%03d" % [out.id, index])
			out.instances.append(_instance(out.id, index, prototype_ids[index], instance_scales[index], fallback, solver.rng.randf_range(-PI, PI)))
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
		out.instances.append(_instance(out.id, index, prototype_ids[index], instance_scales[index], p, solver.rng.randf_range(-PI, PI)))
		index += 1

	while index < count:
		var fallback_result := _weighted_candidate(placement, radius, context, solver, domain, density_profile)
		if not bool(fallback_result.get("ok", false)):
			last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, index, String(fallback_result.get("error", "unknown placement failure"))]
			return false
		var fallback: Vector2 = fallback_result["position"]
		solver.register_occupancy(fallback, radius, "%s:%03d" % [out.id, index])
		out.instances.append(_instance(out.id, index, prototype_ids[index], instance_scales[index], fallback, solver.rng.randf_range(-PI, PI)))
		index += 1
	return true

func _place_clustered(
	out: ResolvedDistribution,
	prototype_ids: Array[String],
	instance_scales: Array[float],
	count: int,
	radius: float,
	placement: Dictionary,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	density_profile: Dictionary,
	realization_profile: Dictionary
) -> bool:
	if count <= 0:
		return true
	var cluster_count := clampi(int(round(sqrt(float(count)) / 2.0)), 2, 6)
	var centers: Array[Vector2] = []
	for _i in range(cluster_count):
		var center_result: Dictionary = _weighted_candidate(placement, 0.0, context, solver, domain, density_profile, realization_profile)
		if not bool(center_result.get("ok", false)):
			last_error = "Placement failed for Distribution '%s' cluster center: %s" % [out.id, String(center_result.get("error", "unknown placement failure"))]
			return false
		centers.append(center_result["position"])

	for i in range(count):
		var center: Vector2 = centers[i % centers.size()]
		var p: Vector2 = center + Vector2.from_angle(solver.rng.randf_range(0.0, TAU)) * solver.rng.randf_range(2.0, 13.0)
		var weight: float = (
			_profile_weight(p, density_profile, domain, context, solver)
			* _realization_weight(p, realization_profile)
		)
		var accepted: bool = (
			domain.has_point(p)
			and solver.is_candidate_valid(p, placement, radius, context)
			and solver.rng.randf() <= weight
		)
		if not accepted:
			var candidate: Dictionary = _weighted_candidate(placement, radius, context, solver, domain, density_profile, realization_profile)
			if not bool(candidate.get("ok", false)):
				last_error = "Placement failed for Distribution '%s' instance %d: %s" % [out.id, i, String(candidate.get("error", "unknown placement failure"))]
				return false
			p = candidate["position"]
		solver.register_occupancy(p, radius, "%s:%03d" % [out.id, i])
		out.instances.append(_instance(out.id, i, prototype_ids[i], instance_scales[i], p, solver.rng.randf_range(-PI, PI)))
	return true

func _weighted_candidate(
	placement: Dictionary,
	radius: float,
	context: Dictionary,
	solver: PlacementSolver,
	domain: Rect2,
	density_profile: Dictionary,
	realization_profile: Dictionary = {}
) -> Dictionary:
	if density_profile.is_empty() and realization_profile.is_empty():
		return solver.try_resolve_candidate(placement, radius, context, domain)

	var best_position: Vector2 = Vector2.ZERO
	var best_weight: float = -1.0
	var found: bool = false
	for _attempt in range(WEIGHTED_ATTEMPTS):
		var result: Dictionary = solver.try_resolve_candidate(placement, radius, context, domain)
		if not bool(result.get("ok", false)):
			continue
		var candidate: Vector2 = result["position"]
		var weight: float = (
			_profile_weight(candidate, density_profile, domain, context, solver)
			* _realization_weight(candidate, realization_profile)
		)
		if weight > best_weight:
			best_position = candidate
			best_weight = weight
			found = true
		if solver.rng.randf() <= weight:
			return {"ok": true, "position": candidate}
	if found:
		return {"ok": true, "position": best_position}
	return {"ok": false, "error": "No valid weighted candidate satisfies placement constraints"}

func _forest_realization_profile(
	out: ResolvedDistribution,
	placement: Dictionary,
	context: Dictionary,
	domain: Rect2
) -> Dictionary:
	if out.semantic_type != "tree":
		return {}
	var forest_id := _relation_target(placement.get("relations", []), "inside")
	var forest: ResolvedRegion = context.get("regions", {}).get(forest_id)
	if forest == null or forest.semantic_type != "forest" or forest.polygon.size() < 3:
		return {}

	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = int(context.get("seed", 0)) ^ int(out.id.hash()) ^ 0x464F5245
	var shortest_side := minf(domain.size.x, domain.size.y)
	var edge_depth := maxf(4.0, shortest_side * FOREST_INTERIOR_DEPTH_RATIO)
	var cluster_radius := maxf(7.0, shortest_side * FOREST_CLUSTER_RADIUS_RATIO)
	var centers: Array[Vector2] = []
	for _center_index in range(FOREST_CLUSTER_COUNT):
		var center := _sample_profile_point(local_rng, domain, forest.polygon, edge_depth * 0.45, centers, cluster_radius * 0.65)
		if center != Vector2.INF:
			centers.append(center)
	if centers.is_empty():
		return {}
	var clearing := _sample_profile_point(local_rng, domain, forest.polygon, edge_depth * 0.25, centers, cluster_radius * 0.8)
	return {
		"polygon": forest.polygon,
		"centers": centers,
		"cluster_radius": cluster_radius,
		"edge_depth": edge_depth,
		"clearing": clearing,
		"clearing_radius": cluster_radius * 0.55,
	}

func _sample_profile_point(
	rng: RandomNumberGenerator,
	domain: Rect2,
	polygon: PackedVector2Array,
	minimum_edge_distance: float,
	avoid: Array[Vector2],
	minimum_separation: float
) -> Vector2:
	var best := Vector2.INF
	var best_score := -INF
	for _attempt in range(64):
		var candidate := Vector2(
			rng.randf_range(domain.position.x, domain.end.x),
			rng.randf_range(domain.position.y, domain.end.y)
		)
		if not Geometry2D.is_point_in_polygon(candidate, polygon):
			continue
		var edge_distance := _distance_to_polygon_edge(candidate, polygon)
		var separation := INF
		for other in avoid:
			separation = minf(separation, candidate.distance_to(other))
		var score := minf(edge_distance / maxf(0.001, minimum_edge_distance), separation / maxf(0.001, minimum_separation))
		if avoid.is_empty():
			score = edge_distance / maxf(0.001, minimum_edge_distance)
		if score > best_score:
			best = candidate
			best_score = score
		if edge_distance >= minimum_edge_distance and (avoid.is_empty() or separation >= minimum_separation):
			return candidate
	return best

func _realization_weight(p: Vector2, profile: Dictionary) -> float:
	if profile.is_empty():
		return 1.0
	var polygon: PackedVector2Array = profile.get("polygon", PackedVector2Array())
	var edge_distance := _distance_to_polygon_edge(p, polygon)
	var edge_t := smoothstep(0.0, float(profile.get("edge_depth", 8.0)), edge_distance)
	var edge_weight := lerpf(FOREST_EDGE_DENSITY, 1.0, edge_t)

	var cluster_radius := float(profile.get("cluster_radius", 10.0))
	var cluster_affinity := 0.0
	for center: Vector2 in profile.get("centers", []):
		cluster_affinity = maxf(cluster_affinity, 1.0 - p.distance_to(center) / cluster_radius)
	cluster_affinity = clampf(cluster_affinity, 0.0, 1.0)
	var cluster_weight := lerpf(0.28, 1.0, pow(cluster_affinity, 1.35))

	var clearing_weight := 1.0
	var clearing: Vector2 = profile.get("clearing", Vector2.INF)
	if clearing != Vector2.INF:
		var clearing_t := clampf(p.distance_to(clearing) / float(profile.get("clearing_radius", 5.0)), 0.0, 1.0)
		clearing_weight = lerpf(0.10, 1.0, smoothstep(0.0, 1.0, clearing_t))
	return clampf(edge_weight * cluster_weight * clearing_weight, 0.025, 1.0)

func _distance_to_polygon_edge(p: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() < 2:
		return 0.0
	var result := INF
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		result = minf(result, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return result

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

func _instance(distribution_id: String, index: int, prototype_id: String, scale: float, p: Vector2, yaw: float) -> Dictionary:
	return {
		"id": "%s:%03d" % [distribution_id, index],
		"prototype_id": prototype_id,
		"transform": Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale),
			Vector3(p.x, 0.0, p.y)
		),
	}
