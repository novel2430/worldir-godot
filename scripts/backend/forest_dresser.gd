class_name ForestDresser
extends RefCounted

# Counts are area budgets, not semantic populations. Larger objects are placed
# first so visual-only grass cannot consume space needed by rocks or accents.
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
const GROUND_HEIGHT := 0.025
const DRESSING_SEED_SALT := 0x44524553

func dress(world: ResolvedWorld, catalog: PrototypeCatalog, solver: PlacementSolver) -> void:
    for region: ResolvedRegion in world.regions:
        if region.semantic_type != "forest" or region.polygon.size() < 3:
            continue
        _dress_forest(region, world, catalog, solver)

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
    for decoration_type in DECORATION_ORDER:
        var rule: Dictionary = RULES[decoration_type]
        var desired_count := mini(
            int(rule["cap"]),
            int(floor(area / float(rule["area_per_instance"])))
        )
        if desired_count <= 0:
            continue
        var prototype_ids := catalog.get_dressing_prototype_ids(decoration_type)
        if prototype_ids.is_empty():
            world.warnings.append("Forest dressing '%s' skipped: no dressing prototype" % decoration_type)
            continue

        var rng := RandomNumberGenerator.new()
        rng.seed = world.seed ^ int(forest.id.hash()) ^ int(decoration_type.hash()) ^ DRESSING_SEED_SALT
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
                    Vector3(point.x, GROUND_HEIGHT, point.y)
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
    for _index in range(count):
        var best := Vector2.INF
        var best_score := -INF
        for _attempt in range(96):
            var point := _random_point(bounds, rng)
            if not Geometry2D.is_point_in_polygon(point, polygon):
                continue
            if solver.overlaps_networks(point, 0.0, networks, 2.0):
                continue
            var edge_distance := _distance_to_polygon_edge(point, polygon)
            var profile_score := _edge_weight(edge_distance, edge_mode)
            var separation := INF
            for center in centers:
                separation = minf(separation, point.distance_to(center))
            var separation_score := 1.0 if centers.is_empty() else clampf(separation / 14.0, 0.0, 1.0)
            var score := profile_score * 0.7 + separation_score * 0.3
            if score > best_score:
                best = point
                best_score = score
            if rng.randf() <= profile_score and (centers.is_empty() or separation >= 8.0):
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
    networks: Array,
    solver: PlacementSolver,
    rng: RandomNumberGenerator
) -> Dictionary:
    var best := Vector2.INF
    var best_weight := -1.0
    for _attempt in range(CANDIDATE_ATTEMPTS):
        var point: Vector2
        if not centers.is_empty() and rng.randf() < CLUSTER_SAMPLE_CHANCE:
            var center := centers[rng.randi_range(0, centers.size() - 1)]
            var cluster_offset := (
                Vector2.from_angle(rng.randf_range(0.0, TAU))
                * sqrt(rng.randf())
                * float(rule["cluster_radius"])
            )
            point = center + cluster_offset
        else:
            point = _random_point(bounds, rng)
        if not Geometry2D.is_point_in_polygon(point, polygon):
            continue
        var edge_distance := _distance_to_polygon_edge(point, polygon)
        var weight := _edge_weight(edge_distance, String(rule["edge_mode"]))
        if solver.overlaps(point, radius):
            continue
        if solver.overlaps_networks(point, radius, networks, float(rule["road_clearance"])):
            continue
        if weight > best_weight:
            best = point
            best_weight = weight
        if rng.randf() <= weight:
            return {"ok": true, "position": point}
    if best != Vector2.INF:
        return {"ok": true, "position": best}
    return {"ok": false}

func _edge_weight(distance: float, mode: String) -> float:
    match mode:
        "edge":
            # Highest several metres inside the forest, with a long low tail so
            # bushes and grass soften the border without forming a perfect ring.
            var outer_ramp := smoothstep(0.2, 2.5, distance)
            var interior_falloff := 1.0 - smoothstep(8.0, 22.0, distance)
            return clampf(0.08 + outer_ramp * interior_falloff * 0.92, 0.08, 1.0)
        "interior":
            return clampf(0.05 + smoothstep(5.0, 16.0, distance) * 0.95, 0.05, 1.0)
        _:
            return clampf(0.55 + (1.0 - smoothstep(10.0, 26.0, distance)) * 0.45, 0.55, 1.0)

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
