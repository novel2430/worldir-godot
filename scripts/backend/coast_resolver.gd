class_name CoastResolver
extends RefCounted

const ResolvedWaterResource = preload("res://scripts/resolved/resolved_water.gd")

const SEA_LEVEL := -0.6
const SHORE_SAMPLES := 49
const BEACH_DEPTH_FRACTION := 0.22
const SHORE_NOISE_M := 1.8
const BOUNDARY_EPSILON_M := 0.15

func resolve(world: ResolvedWorld) -> Array:
    var result: Array = []
    for region: ResolvedRegion in world.regions:
        if region.semantic_type != "coast":
            continue
        var direction := _boundary_direction(region.polygon, world.world_bounds)
        if direction.is_zero_approx():
            world.warnings.append(
                "Coast '%s' does not touch the world boundary; ocean realization skipped" % region.id
            )
            continue
        var water := _build_water(region, world.world_bounds, direction, world.seed)
        if water != null:
            result.append(water)
    return result

func _build_water(region: ResolvedRegion, bounds: Rect2, direction: Vector2, seed_value: int) -> Resource:
    var water: Resource = ResolvedWaterResource.new()
    water.id = "__backend_ocean__%s" % region.id
    water.source_region_id = region.id
    water.sea_level = SEA_LEVEL
    water.seaward_direction = direction
    var region_rect := _polygon_aabb(region.polygon)
    var cross_horizontal := absf(direction.x) > 0.5
    # Once a Coast claims a world edge, the ocean continues along that complete
    # edge. The resolved Coast still supplies the inland shoreline baseline;
    # outside its cross-span the nearest inland extent is used as a calm taper.
    var cross_min := bounds.position.y if cross_horizontal else bounds.position.x
    var cross_max := bounds.end.y if cross_horizontal else bounds.end.x
    var phase := float(abs(seed_value ^ region.id.hash()) % 100003) / 100003.0 * TAU

    for sample_index in range(SHORE_SAMPLES):
        var t := float(sample_index) / float(SHORE_SAMPLES - 1)
        var cross := lerpf(cross_min, cross_max, t)
        var inland_coordinate := _inland_coordinate(region.polygon, direction, cross, region_rect)
        var boundary_coordinate := _boundary_coordinate(bounds, direction)
        var depth := absf(boundary_coordinate - inland_coordinate)
        var noise := (
            sin(t * TAU * 1.7 + phase) * 0.65
            + sin(t * TAU * 4.1 - phase * 0.73) * 0.35
        ) * SHORE_NOISE_M * sin(PI * t)
        var shore_coordinate := inland_coordinate + (
            boundary_coordinate - inland_coordinate
        ) * BEACH_DEPTH_FRACTION + noise * (direction.x + direction.y)
        shore_coordinate = clampf(
            shore_coordinate,
            minf(inland_coordinate, boundary_coordinate) + 0.5,
            maxf(inland_coordinate, boundary_coordinate) - 0.5
        )
        water.shoreline.append(
            Vector2(shore_coordinate, cross) if cross_horizontal else Vector2(cross, shore_coordinate)
        )

    water.polygon = water.shoreline.duplicate()
    var last_cross_point: Vector2 = water.shoreline[water.shoreline.size() - 1]
    var first_cross_point: Vector2 = water.shoreline[0]
    water.polygon.append(_point_on_boundary(last_cross_point, bounds, direction))
    water.polygon.append(_point_on_boundary(first_cross_point, bounds, direction))
    return water

func _boundary_direction(polygon: PackedVector2Array, bounds: Rect2) -> Vector2:
    var contacts := {
        Vector2.LEFT: 0,
        Vector2.RIGHT: 0,
        Vector2.UP: 0,
        Vector2.DOWN: 0,
    }
    for point in polygon:
        if absf(point.x - bounds.position.x) <= BOUNDARY_EPSILON_M:
            contacts[Vector2.LEFT] += 1
        if absf(point.x - bounds.end.x) <= BOUNDARY_EPSILON_M:
            contacts[Vector2.RIGHT] += 1
        if absf(point.y - bounds.position.y) <= BOUNDARY_EPSILON_M:
            contacts[Vector2.UP] += 1
        if absf(point.y - bounds.end.y) <= BOUNDARY_EPSILON_M:
            contacts[Vector2.DOWN] += 1
    var best := Vector2.ZERO
    var best_count := 1
    for direction in contacts:
        var count: int = contacts[direction]
        if count > best_count:
            best = direction
            best_count = count
    return best

func _inland_coordinate(polygon: PackedVector2Array, direction: Vector2, cross: float, fallback: Rect2) -> float:
    var intersections := PackedFloat32Array()
    for index in range(polygon.size()):
        var a := polygon[index]
        var b := polygon[(index + 1) % polygon.size()]
        if absf(direction.x) > 0.5:
            if is_equal_approx(a.y, b.y) or cross < minf(a.y, b.y) or cross > maxf(a.y, b.y):
                continue
            var t := inverse_lerp(a.y, b.y, cross)
            intersections.append(lerpf(a.x, b.x, t))
        else:
            if is_equal_approx(a.x, b.x) or cross < minf(a.x, b.x) or cross > maxf(a.x, b.x):
                continue
            var t := inverse_lerp(a.x, b.x, cross)
            intersections.append(lerpf(a.y, b.y, t))
    if intersections.is_empty():
        if direction == Vector2.RIGHT: return fallback.position.x
        if direction == Vector2.LEFT: return fallback.end.x
        if direction == Vector2.UP: return fallback.end.y
        return fallback.position.y
    var result := intersections[0]
    for value in intersections:
        if direction == Vector2.RIGHT or direction == Vector2.DOWN:
            result = minf(result, value)
        else:
            result = maxf(result, value)
    return result

func _boundary_coordinate(bounds: Rect2, direction: Vector2) -> float:
    if direction == Vector2.RIGHT: return bounds.end.x
    if direction == Vector2.LEFT: return bounds.position.x
    if direction == Vector2.UP: return bounds.position.y
    return bounds.end.y

func _point_on_boundary(point: Vector2, bounds: Rect2, direction: Vector2) -> Vector2:
    if direction == Vector2.RIGHT: return Vector2(bounds.end.x, point.y)
    if direction == Vector2.LEFT: return Vector2(bounds.position.x, point.y)
    if direction == Vector2.UP: return Vector2(point.x, bounds.position.y)
    return Vector2(point.x, bounds.end.y)

func _polygon_aabb(polygon: PackedVector2Array) -> Rect2:
    if polygon.is_empty():
        return Rect2()
    var minimum := polygon[0]
    var maximum := polygon[0]
    for point in polygon:
        minimum = minimum.min(point)
        maximum = maximum.max(point)
    return Rect2(minimum, maximum - minimum)
