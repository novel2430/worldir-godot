class_name TerrainResolver
extends RefCounted

const ResolvedTerrainResource = preload("res://scripts/resolved/resolved_terrain.gd")

const GRID_SIZE := 129
const ROAD_SURFACE_OFFSET := 0.025
const INSTANCE_SURFACE_OFFSET := 0.02
const REGION_OUTER_BLEND_M := 3.5
const REGION_INNER_BLEND_M := 5.5
const ROAD_SHOULDER_M := 2.6
const ROAD_TERRAIN_BLEND_M := 3.4
const BUILDING_DIRT_FADE_M := 2.3
const BUILDING_PATH_MAX_LENGTH_M := 26.0
const COAST_LAND_BLEND_M := 12.0
const COAST_WET_SAND_M := 4.5
const COAST_UNDERWATER_SLOPE := 0.035
const BASE_HEIGHT_LIMIT := 2.8
const FOREST_HEIGHT_LIMIT := 3.55
const FOREST_RELIEF_STRENGTH := 0.78

func resolve(world: ResolvedWorld, catalog: PrototypeCatalog) -> Resource:
    var terrain: Resource = ResolvedTerrainResource.new()
    terrain.world_bounds = world.world_bounds
    terrain.grid_size = GRID_SIZE
    terrain.road_surface_offset = ROAD_SURFACE_OFFSET
    terrain.heights.resize(GRID_SIZE * GRID_SIZE)
    terrain.surface_masks.resize(GRID_SIZE * GRID_SIZE)
    terrain.shore_wetness.resize(GRID_SIZE * GRID_SIZE)
    var building_influences := _building_influences(world, catalog)
    _assign_building_targets(building_influences, world)

    for z_index in range(GRID_SIZE):
        for x_index in range(GRID_SIZE):
            var point := _grid_point(world.world_bounds, x_index, z_index)
            var masks := _surface_masks(point, world, building_influences)
            var height := _environment_height(point, world, masks)
            height = _shape_coasts(point, height, world)
            height = _flatten_for_roads(point, height, world)
            height = _flatten_for_buildings(point, height, building_influences)
            var index := z_index * GRID_SIZE + x_index
            terrain.heights[index] = height
            terrain.surface_masks[index] = masks
            terrain.shore_wetness[index] = _shore_wetness(point, world)
    return terrain

func conform_world(world: ResolvedWorld) -> void:
    if world.terrain == null:
        return
    for network: ResolvedNetwork in world.networks:
        for index in range(network.curve_points.size()):
            var point := network.curve_points[index]
            point.y = world.terrain.sample_height(Vector2(point.x, point.z)) + ROAD_SURFACE_OFFSET
            network.curve_points[index] = point
    for entity: ResolvedEntity in world.entities:
        entity.transform.origin.y = world.terrain.sample_height(
            Vector2(entity.transform.origin.x, entity.transform.origin.z)
        ) + INSTANCE_SURFACE_OFFSET
    for distribution: ResolvedDistribution in world.distributions:
        for instance in distribution.instances:
            var transform: Transform3D = instance["transform"]
            transform.origin.y = world.terrain.sample_height(Vector2(transform.origin.x, transform.origin.z)) + INSTANCE_SURFACE_OFFSET
            instance["transform"] = transform

func _surface_masks(point: Vector2, world: ResolvedWorld, buildings: Array) -> Color:
    var forest := 0.0
    var settlement := 0.0
    var coast := 0.0
    for region: ResolvedRegion in world.regions:
        var influence := _region_influence(point, region.polygon)
        match region.semantic_type:
            "forest", "swamp": forest = maxf(forest, influence)
            "town", "village", "district": settlement = maxf(settlement, influence)
            "coast": coast = maxf(coast, influence)

    for water in world.waters:
        var shore_distance: float = water.signed_distance_to_shore(point)
        var beach_influence: float = smoothstep(-18.0, -5.0, shore_distance) * water.cross_span_influence(point)
        coast = maxf(coast, beach_influence)

    var local_dirt := _road_influence(point, world.networks)
    for building in buildings:
        var center: Vector2 = building["center"]
        var radius := float(building["radius"])
        local_dirt = maxf(local_dirt, 1.0 - smoothstep(radius, radius + BUILDING_DIRT_FADE_M, point.distance_to(center)))
        var road_point: Vector2 = building.get("road_point", Vector2.INF)
        if road_point != Vector2.INF:
            var path_distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point, center, road_point))
            local_dirt = maxf(local_dirt, 1.0 - smoothstep(0.55, 1.45, path_distance))
    return Color(forest, settlement, coast, clampf(local_dirt, 0.0, 1.0))

func _environment_height(point: Vector2, world: ResolvedWorld, masks: Color) -> float:
    var phase := _seed_phase(world.seed)
    var broad := (
        sin(point.x * 0.027 + phase) * 1.05
        + cos(point.y * 0.023 - phase * 0.73) * 0.85
        + sin((point.x + point.y) * 0.014 + phase * 1.41) * 0.65
    )
    var detail := (
        sin(point.x * 0.071 - point.y * 0.043 + phase * 2.1) * 0.32
        + cos(point.x * 0.049 + point.y * 0.061 - phase) * 0.24
    )
    var height := broad + detail

    # Forest keeps the shared macro landform, then adds a slower rolling ridge
    # and amplifies some mid-frequency variation. The resolved forest mask
    # feathers this personality at the Region edge; roads and building pads are
    # graded afterward and therefore remain usable inside a hilly forest.
    var forest_relief := (
        sin(point.x * 0.041 + point.y * 0.026 + phase * 0.61) * 0.56
        + cos(point.x * 0.019 - point.y * 0.044 - phase * 1.23) * 0.42
        + detail * 0.48
    )
    height += forest_relief * masks.r * FOREST_RELIEF_STRENGTH

    # Region personality belongs to the terrain realization. Local road and
    # building grading is applied in separate passes so it can use their true
    # resolved geometry instead of treating the dirt-color mask as elevation.
    for region: ResolvedRegion in world.regions:
        if region.semantic_type != "town" and region.semantic_type != "village" and region.semantic_type != "district":
            continue
        var influence := _region_influence(point, region.polygon)
        if influence <= 0.0:
            continue
        var center := _polygon_center(region.polygon)
        var target := _macro_height(center, world.seed)
        height = lerpf(height, target, influence * 0.82)
    var height_limit := lerpf(BASE_HEIGHT_LIMIT, FOREST_HEIGHT_LIMIT, masks.r)
    return clampf(height, -height_limit, height_limit)

func _shape_coasts(point: Vector2, height: float, world: ResolvedWorld) -> float:
    var result := height
    for water in world.waters:
        var cross_influence: float = water.cross_span_influence(point)
        if cross_influence <= 0.0:
            continue
        var distance: float = water.signed_distance_to_shore(point)
        if distance < -COAST_LAND_BLEND_M:
            continue
        var target := result
        var influence := cross_influence
        if distance < 0.0:
            var beach_t := smoothstep(-COAST_LAND_BLEND_M, 0.0, distance)
            target = lerpf(water.sea_level + 0.62, water.sea_level - 0.06, beach_t)
            influence *= beach_t
        else:
            target = water.sea_level - 0.14 - minf(distance * COAST_UNDERWATER_SLOPE, 1.8)
        result = lerpf(result, target, influence)
    return clampf(result, -FOREST_HEIGHT_LIMIT, FOREST_HEIGHT_LIMIT)

func _shore_wetness(point: Vector2, world: ResolvedWorld) -> float:
    var result := 0.0
    for water in world.waters:
        var distance: float = water.signed_distance_to_shore(point)
        if distance > 0.8 or distance < -COAST_WET_SAND_M:
            continue
        var land_fade := smoothstep(-COAST_WET_SAND_M, -0.25, distance)
        var water_fade := 1.0 - smoothstep(-0.1, 0.8, distance)
        result = maxf(result, land_fade * water_fade * water.cross_span_influence(point))
    return result

func _flatten_for_roads(point: Vector2, height: float, world: ResolvedWorld) -> float:
    var result := height
    var solver := PlacementSolver.new()
    for network: ResolvedNetwork in world.networks:
        if network.curve_points.size() < 2:
            continue
        var nearest := solver.nearest_point_on_network(point, network)
        var distance := point.distance_to(nearest)
        var half_width := network.width * 0.5
        var influence := 1.0 - smoothstep(half_width, half_width + ROAD_TERRAIN_BLEND_M, distance)
        if influence <= 0.0:
            continue
        # The target still follows the road longitudinally through the macro
        # landform. Across its width, however, the terrain converges to one
        # local centerline height and then eases back through the shoulder.
        var target_masks := _surface_masks_without_local_dirt(nearest, world)
        var target_height := _shape_coasts(nearest, _environment_height(nearest, world, target_masks), world)
        result = lerpf(result, target_height, influence)
    return result

func _flatten_for_buildings(point: Vector2, height: float, buildings: Array) -> float:
    var result := height
    for building in buildings:
        var center: Vector2 = building["center"]
        var radius := float(building["flatten_radius"])
        var influence := 1.0 - smoothstep(radius, radius + 2.8, point.distance_to(center))
        if influence > 0.0:
            result = lerpf(result, float(building["target_height"]), influence)
    return result

func _building_influences(world: ResolvedWorld, catalog: PrototypeCatalog) -> Array:
    var result: Array = []
    for entity: ResolvedEntity in world.entities:
        var meta := catalog.get_metadata(entity.prototype_id)
        var footprint: Vector2 = meta.get("visual_footprint", Vector2.ONE * 4.0)
        result.append(_building_influence(
            Vector2(entity.transform.origin.x, entity.transform.origin.z),
            maxf(footprint.x, footprint.y) * 0.5 + 1.0,
            world.networks
        ))
    for distribution: ResolvedDistribution in world.distributions:
        if distribution.semantic_type != "house":
            continue
        for instance in distribution.instances:
            var meta := catalog.get_metadata(String(instance["prototype_id"]))
            var footprint: Vector2 = meta.get("visual_footprint", Vector2.ONE * 4.0)
            var transform: Transform3D = instance["transform"]
            var scale := transform.basis.get_scale().x
            result.append(_building_influence(
                Vector2(transform.origin.x, transform.origin.z),
                maxf(footprint.x, footprint.y) * scale * 0.5 + 0.8,
                world.networks
            ))
    return result

func _building_influence(center: Vector2, radius: float, networks: Array) -> Dictionary:
    var closest := Vector2.INF
    var closest_distance := INF
    var solver := PlacementSolver.new()
    for network: ResolvedNetwork in networks:
        var point := solver.nearest_point_on_network(center, network)
        var distance := center.distance_to(point)
        if distance < closest_distance:
            closest = point
            closest_distance = distance
    if closest_distance > BUILDING_PATH_MAX_LENGTH_M:
        closest = Vector2.INF
    return {
        "center": center,
        "radius": radius,
        "flatten_radius": maxf(1.5, radius - 0.8),
        "road_point": closest,
        "target_height": 0.0,
    }

func _assign_building_targets(buildings: Array, world: ResolvedWorld) -> void:
    for building in buildings:
        var center: Vector2 = building["center"]
        var masks := _surface_masks_without_buildings(center, world)
        building["target_height"] = _shape_coasts(center, _environment_height(center, world, masks), world)

func _surface_masks_without_buildings(point: Vector2, world: ResolvedWorld) -> Color:
    var result := _surface_masks_without_local_dirt(point, world)
    result.a = _road_influence(point, world.networks)
    return result

func _surface_masks_without_local_dirt(point: Vector2, world: ResolvedWorld) -> Color:
    var forest := 0.0
    var settlement := 0.0
    var coast := 0.0
    for region: ResolvedRegion in world.regions:
        var influence := _region_influence(point, region.polygon)
        match region.semantic_type:
            "forest", "swamp": forest = maxf(forest, influence)
            "town", "village", "district": settlement = maxf(settlement, influence)
            "coast": coast = maxf(coast, influence)
    return Color(forest, settlement, coast, 0.0)

func _road_influence(point: Vector2, networks: Array) -> float:
    var result := 0.0
    var solver := PlacementSolver.new()
    for network: ResolvedNetwork in networks:
        var distance := point.distance_to(solver.nearest_point_on_network(point, network))
        result = maxf(result, 1.0 - smoothstep(network.width * 0.5, network.width * 0.5 + ROAD_SHOULDER_M, distance))
    return result

func _region_influence(point: Vector2, polygon: PackedVector2Array) -> float:
    if polygon.size() < 3:
        return 0.0
    var distance := _distance_to_polygon_edge(point, polygon)
    var signed_distance := distance if Geometry2D.is_point_in_polygon(point, polygon) else -distance
    return smoothstep(-REGION_OUTER_BLEND_M, REGION_INNER_BLEND_M, signed_distance)

func _distance_to_polygon_edge(point: Vector2, polygon: PackedVector2Array) -> float:
    var result := INF
    for index in range(polygon.size()):
        var closest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
        result = minf(result, point.distance_to(closest))
    return result

func _grid_point(bounds: Rect2, x_index: int, z_index: int) -> Vector2:
    return Vector2(
        lerpf(bounds.position.x, bounds.end.x, float(x_index) / float(GRID_SIZE - 1)),
        lerpf(bounds.position.y, bounds.end.y, float(z_index) / float(GRID_SIZE - 1))
    )

func _polygon_center(polygon: PackedVector2Array) -> Vector2:
    var result := Vector2.ZERO
    for point in polygon:
        result += point
    return result / float(maxi(1, polygon.size()))

func _macro_height(point: Vector2, seed_value: int) -> float:
    var phase := _seed_phase(seed_value)
    return (
        sin(point.x * 0.027 + phase) * 1.05
        + cos(point.y * 0.023 - phase * 0.73) * 0.85
        + sin((point.x + point.y) * 0.014 + phase * 1.41) * 0.65
    )

func _seed_phase(seed_value: int) -> float:
    return float(abs(seed_value) % 100003) / 100003.0 * TAU
