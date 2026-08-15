class_name ResolvedChunk
extends ResolvedWorld

var coord := Vector2i.ZERO
var bounds := Rect2()
var revision := -1
var boundary_summary: Dictionary = {}
var generation_constraints: ChunkBoundaryConstraints = null

func absorb_world(world: ResolvedWorld) -> void:
	seed = world.seed
	realization_seed = world.realization_seed
	environment = world.environment.duplicate(true)
	world_bounds = world.world_bounds
	bounds = world.world_bounds
	terrain = world.terrain
	waters = world.waters
	regions = world.regions
	networks = world.networks
	entities = world.entities
	distributions = world.distributions
	decorations = world.decorations
	warnings = world.warnings
	errors = world.errors

func deterministic_signature() -> String:
	var value := {
		"coord": [coord.x, coord.y],
		"bounds": _rect_value(bounds),
		"revision": revision,
		"seed": seed,
		"terrain": _terrain_value(),
		"waters": _water_values(),
		"regions": _region_values(),
		"networks": _network_values(),
		"entities": _entity_values(),
		"distributions": _distribution_values(),
		"decorations": _decoration_values(),
		"environment": _canonical_variant(environment),
	}
	return JSON.stringify(value)

func _terrain_value() -> Dictionary:
	if terrain == null:
		return {}
	var heights: Array = []
	for height in terrain.heights:
		heights.append(snappedf(float(height), 0.00001))
	var masks: Array = []
	for mask: Color in terrain.surface_masks:
		masks.append([
			snappedf(mask.r, 0.00001),
			snappedf(mask.g, 0.00001),
			snappedf(mask.b, 0.00001),
			snappedf(mask.a, 0.00001),
		])
	var shore: Array = []
	for value in terrain.shore_wetness:
		shore.append(snappedf(float(value), 0.00001))
	return {"grid_size": terrain.grid_size, "heights": heights, "masks": masks, "shore": shore}

func _water_values() -> Array:
	var result: Array = []
	for water in waters:
		var shoreline: Array = []
		for point: Vector2 in water.shoreline:
			shoreline.append(_canonical_variant(point))
		var polygon: Array = []
		for point: Vector2 in water.polygon:
			polygon.append(_canonical_variant(point))
		result.append({
			"id": String(water.id),
			"source_region_id": String(water.source_region_id),
			"sea_level": snappedf(float(water.sea_level), 0.00001),
			"seaward_direction": _canonical_variant(water.seaward_direction),
			"shoreline": shoreline,
			"polygon": polygon,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	return result

func _region_values() -> Array:
	var result: Array = []
	for region: ResolvedRegion in regions:
		var polygon: Array = []
		for point: Vector2 in region.polygon:
			polygon.append([snappedf(point.x, 0.00001), snappedf(point.y, 0.00001)])
		result.append({"id": region.id, "type": region.semantic_type, "polygon": polygon})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	return result

func _network_values() -> Array:
	var result: Array = []
	for network: ResolvedNetwork in networks:
		var points: Array = []
		for point: Vector3 in network.curve_points:
			points.append(_vector3_value(point))
		result.append({"id": network.id, "width": network.width, "points": points})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	return result

func _entity_values() -> Array:
	var result: Array = []
	for entity: ResolvedEntity in entities:
		result.append({
			"id": entity.id,
			"prototype": entity.prototype_id,
			"transform": _transform_value(entity.transform),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	return result

func _distribution_values() -> Array:
	var result: Array = []
	for distribution: ResolvedDistribution in distributions:
		var instances: Array = []
		for instance: Dictionary in distribution.instances:
			instances.append({
				"id": String(instance.get("id", "")),
				"prototype": String(instance.get("prototype_id", "")),
				"transform": _transform_value(instance.get("transform", Transform3D.IDENTITY)),
			})
		result.append({"id": distribution.id, "instances": instances})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	return result

func _decoration_values() -> Array:
	var result: Array = []
	for decoration: ResolvedDecoration in decorations:
		var instances: Array = []
		for instance: Dictionary in decoration.instances:
			instances.append({
				"id": String(instance.get("id", "")),
				"prototype": String(instance.get("prototype_id", "")),
				"transform": _transform_value(instance.get("transform", Transform3D.IDENTITY)),
			})
		result.append({"id": decoration.id, "instances": instances})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	return result

func _transform_value(value: Transform3D) -> Array:
	return [
		_vector3_value(value.basis.x),
		_vector3_value(value.basis.y),
		_vector3_value(value.basis.z),
		_vector3_value(value.origin),
	]

func _vector3_value(value: Vector3) -> Array:
	return [
		snappedf(value.x, 0.00001),
		snappedf(value.y, 0.00001),
		snappedf(value.z, 0.00001),
	]

func _rect_value(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]

func _canonical_variant(value: Variant) -> Variant:
	if value is float:
		return snappedf(value, 0.00001)
	if value is Vector2:
		return [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001)]
	if value is Vector3:
		return _vector3_value(value)
	if value is Color:
		return [snappedf(value.r, 0.00001), snappedf(value.g, 0.00001), snappedf(value.b, 0.00001), snappedf(value.a, 0.00001)]
	if value is PackedVector2Array:
		var points: Array = []
		for point: Vector2 in value:
			points.append(_canonical_variant(point))
		return points
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_canonical_variant(item))
		return array
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant): return String(a) < String(b))
		for key in keys:
			result[String(key)] = _canonical_variant(value[key])
		return result
	return value
