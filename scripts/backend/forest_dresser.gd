class_name ForestDresser
extends RefCounted

const RealizationPolicyScript = preload("res://scripts/backend/realization_policy.gd")

# Compatibility fallbacks for the live realization policy. Counts remain
# Backend-owned visual budgets, never semantic World IR populations. Larger
# objects are placed first so grass cannot consume their occupancy.
const DECORATION_ORDER: Array[String] = ["dead_tree", "rock", "bush", "grass"]
const RULES := {
    "dead_tree": {
        "area_per_instance": 3800.0,
        "cap": 4,
        "cluster_count": 0,
        "cluster_radius": 0.0,
        "edge_mode": "interior",
        "road_clearance": 2.0,
    },
    "rock": {
        "area_per_instance": 780.0,
        "cap": 18,
        "cluster_count": 3,
        "cluster_radius": 3.8,
        "edge_mode": "mixed",
        "road_clearance": 1.5,
    },
    "bush": {
        "area_per_instance": 250.0,
        "cap": 55,
        "cluster_count": 5,
        "cluster_radius": 6.0,
        "edge_mode": "edge",
        "road_clearance": 1.0,
    },
    "grass": {
        "area_per_instance": 100.0,
        "cap": 120,
        "cluster_count": 7,
        "cluster_radius": 7.0,
        "edge_mode": "edge",
        "road_clearance": 0.55,
    },
}
const CANDIDATE_ATTEMPTS := 140
const CLUSTER_SAMPLE_CHANCE := 0.82
const GROUND_OFFSET := 0.02
const DRESSING_SEED_SALT := 0x44524553

var realization_policy: RefCounted = RealizationPolicyScript.new()

func dress(world: ResolvedWorld, catalog: PrototypeCatalog, solver: PlacementSolver) -> void:
    for warning in realization_policy.warnings:
        if not (warning in world.warnings):
            world.warnings.append(warning)
    var dressing_region_types: Array[String] = realization_policy.string_array(
        "dressing.region_types",
        ["forest"]
    )
    for region: ResolvedRegion in world.regions:
        if not (region.semantic_type in dressing_region_types) or region.polygon.size() < 3:
            continue
        _dress_forest(region, world, catalog, solver)

func target_count_for_area(area_m2: float, rule: Dictionary) -> int:
    var cap := int(rule.get("cap", 0))
    var candidate_area := float(rule.get("target_area_per_candidate_m2", 0.0))
    if cap <= 0 or area_m2 <= 0.0:
        return 0
    if candidate_area > 0.0:
        var candidate_count := int(floor(area_m2 / candidate_area))
        var acceptance := clampf(float(rule.get("acceptance_probability", 1.0)), 0.0, 1.0)
        return mini(cap, int(round(float(candidate_count) * acceptance)))
    var legacy_area := float(rule.get(
        "legacy_area_per_instance_m2",
        rule.get("area_per_instance", 0.0)
    ))
    return 0 if legacy_area <= 0.0 else mini(cap, int(floor(area_m2 / legacy_area)))

func _dress_forest(
    forest: ResolvedRegion,
    world: ResolvedWorld,
    catalog: PrototypeCatalog,
    solver: PlacementSolver
) -> void:
    var area := _polygon_area(forest.polygon)
    if area <= 0.0:
        return
    var bounds := solver.polygon_aabb(forest.polygon)
    var structure_influences := _structure_influences(world, catalog)
    for decoration_type in DECORATION_ORDER:
        var rule: Dictionary = realization_policy.dressing_rule(
            decoration_type,
            RULES[decoration_type]
        )
        var desired_count := target_count_for_area(area, rule)
        if desired_count <= 0:
            continue
        var prototype_ids := catalog.get_dressing_prototype_ids(decoration_type)
        if prototype_ids.is_empty():
            world.warnings.append("Forest dressing '%s' skipped: no dressing prototype" % decoration_type)
            continue

        var rng := RandomNumberGenerator.new()
        rng.seed = world.realization_seed ^ int(forest.id.hash()) ^ int(decoration_type.hash()) ^ DRESSING_SEED_SALT
        var centers := _cluster_centers(
            int(rule["cluster_count"]),
            forest.polygon,
            bounds,
            String(rule["edge_mode"]),
            world.networks,
            solver,
            rng
        )
        var decoration := ResolvedDecoration.new()
        decoration.id = "__backend_forest_dressing__%s__%s" % [forest.id, decoration_type]
        decoration.region_id = forest.id
        decoration.decoration_type = decoration_type

        for index in range(desired_count):
            var variant := catalog.choose_population_variant(prototype_ids, rng)
            var prototype_id := String(variant.get("prototype_id", ""))
            var scale := float(variant.get("scale", 1.0))
            var meta := catalog.get_metadata(prototype_id)
            var radius := maxf(0.08, float(meta.get("population_occupancy_radius", 0.25)) * scale)
            var candidate := _try_candidate(
                forest.polygon,
                bounds,
                radius,
                centers,
                rule,
                decoration_type,
                structure_influences,
                world.networks,
                solver,
                rng
            )
            if not bool(candidate.get("ok", false)):
                continue
            var point: Vector2 = candidate["position"]
            solver.register_occupancy(point, radius, "%s:%03d" % [decoration.id, index])
            decoration.instances.append({
                "id": "%s:%03d" % [decoration.id, index],
                "prototype_id": prototype_id,
                "transform": Transform3D(
                    Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale),
                    Vector3(
                        point.x,
                        (world.terrain.sample_height(point) if world.terrain != null else 0.0) + GROUND_OFFSET,
                        point.y
                    )
                ),
                "occupancy_radius": radius,
            })

        if not decoration.instances.is_empty():
            world.decorations.append(decoration)
        if decoration.instances.size() < desired_count:
            world.warnings.append(
                "Forest dressing '%s' in '%s' placed %d/%d instances (best effort)"
                % [decoration_type, forest.id, decoration.instances.size(), desired_count]
            )

func _cluster_centers(
    count: int,
    polygon: PackedVector2Array,
    bounds: Rect2,
    edge_mode: String,
    networks: Array,
    solver: PlacementSolver,
    rng: RandomNumberGenerator
) -> Array[Vector2]:
    var centers: Array[Vector2] = []
    var center_attempts: int = realization_policy.integer(
        "dressing.cluster_center_attempts",
        96
    )
    var minimum_separation: float = realization_policy.positive_number(
        "dressing.cluster_center_minimum_separation_m",
        8.0
    )
    var separation_score_distance: float = realization_policy.positive_number(
        "dressing.cluster_separation_score_distance_m",
        14.0
    )
    var profile_score_weight: float = realization_policy.probability(
        "dressing.cluster_profile_score_weight",
        0.70
    )
    for _index in range(count):
        var best: Vector2 = Vector2.INF
        var best_score: float = -INF
        for _attempt in range(maxi(1, center_attempts)):
            var point: Vector2 = _random_point(bounds, rng)
            if not Geometry2D.is_point_in_polygon(point, polygon):
                continue
            if solver.overlaps_networks(point, 0.0, networks, 2.0):
                continue
            var edge_distance: float = _distance_to_polygon_edge(point, polygon)
            var profile_score: float = _edge_weight(edge_distance, edge_mode)
            var separation: float = INF
            for center in centers:
                separation = minf(separation, point.distance_to(center))
            var separation_score: float = (
                1.0
                if centers.is_empty()
                else clampf(separation / separation_score_distance, 0.0, 1.0)
            )
            var score: float = (
                profile_score * profile_score_weight
                + separation_score * (1.0 - profile_score_weight)
            )
            if score > best_score:
                best = point
                best_score = score
            if (
                rng.randf() <= profile_score
                and (centers.is_empty() or separation >= minimum_separation)
            ):
                best = point
                break
        if best != Vector2.INF:
            centers.append(best)
    return centers

func _try_candidate(
    polygon: PackedVector2Array,
    bounds: Rect2,
    radius: float,
    centers: Array[Vector2],
    rule: Dictionary,
    decoration_type: String,
    structure_influences: Array,
    networks: Array,
    solver: PlacementSolver,
    rng: RandomNumberGenerator
) -> Dictionary:
    var best: Vector2 = Vector2.INF
    var best_weight: float = -1.0
    var candidate_attempts: int = realization_policy.integer(
        "dressing.candidate_attempts",
        CANDIDATE_ATTEMPTS
    )
    var cluster_probability: float = realization_policy.probability(
        "dressing.cluster_sample_probability",
        CLUSTER_SAMPLE_CHANCE
    )
    for _attempt in range(maxi(1, candidate_attempts)):
        var point: Vector2
        if not centers.is_empty() and rng.randf() < cluster_probability:
            var center: Vector2 = centers[rng.randi_range(0, centers.size() - 1)]
            var cluster_offset: Vector2 = (
                Vector2.from_angle(rng.randf_range(0.0, TAU))
                * sqrt(rng.randf())
                * float(rule.get("cluster_radius_m", rule.get("cluster_radius", 0.0)))
            )
            point = center + cluster_offset
        else:
            point = _random_point(bounds, rng)
        if not Geometry2D.is_point_in_polygon(point, polygon):
            continue
        var edge_distance: float = _distance_to_polygon_edge(point, polygon)
        var weight: float = _edge_weight(edge_distance, String(rule["edge_mode"]))
        if solver.overlaps(point, radius):
            continue
        var road_clearance: float = float(rule.get(
            "road_clearance_m",
            rule.get("road_clearance", 0.0)
        ))
        if solver.overlaps_networks(point, radius, networks, road_clearance):
            continue
        weight *= _building_clearing_weight(
            point,
            decoration_type,
            structure_influences
        )
        weight *= _network_corridor_weight(
            point,
            radius,
            road_clearance,
            decoration_type,
            networks,
            solver
        )
        if weight > best_weight:
            best = point
            best_weight = weight
        if rng.randf() <= weight:
            return {"ok": true, "position": point}
    if best != Vector2.INF:
        return {"ok": true, "position": best}
    return {"ok": false}

func _structure_influences(world: ResolvedWorld, catalog: PrototypeCatalog) -> Array:
    var result: Array = []
    for entity: ResolvedEntity in world.entities:
        var meta := catalog.get_metadata(entity.prototype_id)
        var footprint: Vector2 = meta.get("visual_footprint", Vector2.ZERO)
        var scale := entity.transform.basis.get_scale()
        var radius := maxf(footprint.x * scale.x, footprint.y * scale.z) * 0.5
        radius = maxf(radius, float(meta.get("placement_radius", 1.0)))
        result.append({
            "position": Vector2(entity.transform.origin.x, entity.transform.origin.z),
            "radius": radius,
        })
    for distribution: ResolvedDistribution in world.distributions:
        if distribution.semantic_type != "house":
            continue
        for instance: Dictionary in distribution.instances:
            var prototype_id := String(instance.get("prototype_id", ""))
            var meta := catalog.get_metadata(prototype_id)
            var footprint: Vector2 = meta.get("visual_footprint", Vector2.ZERO)
            var transform: Transform3D = instance.get("transform", Transform3D.IDENTITY)
            var scale := transform.basis.get_scale()
            var radius := maxf(footprint.x * scale.x, footprint.y * scale.z) * 0.5
            radius = maxf(radius, float(meta.get("placement_radius", 1.0)))
            result.append({
                "position": Vector2(transform.origin.x, transform.origin.z),
                "radius": radius,
            })
    return result

func _building_clearing_weight(
    point: Vector2,
    decoration_type: String,
    influences: Array
) -> float:
    if influences.is_empty():
        return 1.0
    var minimum_inner: float = realization_policy.positive_number(
        "dressing.building_clearing.minimum_inner_radius_m",
        4.0
    )
    var minimum_outer: float = realization_policy.positive_number(
        "dressing.building_clearing.minimum_outer_radius_m",
        12.0
    )
    var inner_scale: float = realization_policy.positive_number(
        "dressing.building_clearing.footprint_inner_scale",
        1.6
    )
    var outer_scale: float = realization_policy.positive_number(
        "dressing.building_clearing.footprint_outer_scale",
        3.0
    )
    var minimum_multiplier: float = realization_policy.probability(
        "dressing.building_clearing.minimum_multiplier.%s" % decoration_type,
        0.1
    )
    var result: float = 1.0
    for influence: Dictionary in influences:
        var structure_radius: float = maxf(0.1, float(influence.get("radius", 1.0)))
        var inner: float = maxf(minimum_inner, structure_radius * inner_scale)
        var outer: float = maxf(inner + 0.1, maxf(minimum_outer, structure_radius * outer_scale))
        var distance: float = point.distance_to(influence.get("position", Vector2.INF))
        result = minf(
            result,
            lerpf(minimum_multiplier, 1.0, smoothstep(inner, outer, distance))
        )
    return result

func _network_corridor_weight(
    point: Vector2,
    radius: float,
    hard_clearance: float,
    decoration_type: String,
    networks: Array,
    solver: PlacementSolver
) -> float:
    var result: float = 1.0
    for network: ResolvedNetwork in networks:
        var network_type := String(network.semantic_type)
        var corridor: Dictionary = realization_policy.dictionary(
            "dressing.network_corridors.%s" % network_type
        )
        if corridor.is_empty():
            continue
        var nearest: Vector2 = solver.nearest_point_on_network(point, network)
        var distance_from_edge: float = maxf(
            0.0,
            point.distance_to(nearest) - network.width * 0.5
        )
        var inner: float = radius + hard_clearance
        var outer: float = radius + maxf(
            hard_clearance + 0.1,
            float(corridor.get("outer_extra_width_m", hard_clearance))
        )
        var minimums: Dictionary = corridor.get("minimum_multiplier", {})
        var minimum_multiplier: float = clampf(
            float(minimums.get(decoration_type, 0.1)),
            0.0,
            1.0
        )
        result = minf(
            result,
            lerpf(
                minimum_multiplier,
                1.0,
                smoothstep(inner, outer, distance_from_edge)
            )
        )
    return result

func _edge_weight(distance: float, mode: String) -> float:
    match mode:
        "edge":
            # Highest several metres inside the forest, with a long low tail so
            # bushes and grass soften the border without forming a perfect ring.
            var edge_minimum: float = realization_policy.probability(
                "dressing.edge_profiles.edge.minimum_multiplier",
                0.08
            )
            var outer_ramp: float = smoothstep(
                realization_policy.number("dressing.edge_profiles.edge.outer_ramp_start_m", 0.2),
                realization_policy.number("dressing.edge_profiles.edge.outer_ramp_end_m", 2.5),
                distance
            )
            var interior_falloff: float = 1.0 - smoothstep(
                realization_policy.number("dressing.edge_profiles.edge.interior_falloff_start_m", 8.0),
                realization_policy.number("dressing.edge_profiles.edge.interior_falloff_end_m", 22.0),
                distance
            )
            return clampf(
                edge_minimum + outer_ramp * interior_falloff * (1.0 - edge_minimum),
                edge_minimum,
                1.0
            )
        "interior":
            var interior_minimum: float = realization_policy.probability(
                "dressing.edge_profiles.interior.minimum_multiplier",
                0.05
            )
            return clampf(
                interior_minimum + smoothstep(
                    realization_policy.number("dressing.edge_profiles.interior.ramp_start_m", 5.0),
                    realization_policy.number("dressing.edge_profiles.interior.ramp_end_m", 16.0),
                    distance
                ) * (1.0 - interior_minimum),
                interior_minimum,
                1.0
            )
        _:
            var mixed_minimum: float = realization_policy.probability(
                "dressing.edge_profiles.mixed.minimum_multiplier",
                0.55
            )
            return clampf(
                mixed_minimum + (1.0 - smoothstep(
                    realization_policy.number("dressing.edge_profiles.mixed.falloff_start_m", 10.0),
                    realization_policy.number("dressing.edge_profiles.mixed.falloff_end_m", 26.0),
                    distance
                )) * (1.0 - mixed_minimum),
                mixed_minimum,
                1.0
            )

func _random_point(bounds: Rect2, rng: RandomNumberGenerator) -> Vector2:
    return Vector2(
        rng.randf_range(bounds.position.x, bounds.end.x),
        rng.randf_range(bounds.position.y, bounds.end.y)
    )

func _polygon_area(polygon: PackedVector2Array) -> float:
    var twice_area := 0.0
    for index in range(polygon.size()):
        var a := polygon[index]
        var b := polygon[(index + 1) % polygon.size()]
        twice_area += a.x * b.y - b.x * a.y
    return absf(twice_area) * 0.5

func _distance_to_polygon_edge(point: Vector2, polygon: PackedVector2Array) -> float:
    var result := INF
    for index in range(polygon.size()):
        var closest := Geometry2D.get_closest_point_to_segment(
            point,
            polygon[index],
            polygon[(index + 1) % polygon.size()]
        )
        result = minf(result, point.distance_to(closest))
    return result
