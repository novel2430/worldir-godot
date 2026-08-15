class_name SceneDiff
extends RefCounted

const FLOAT_EPSILON := 0.001

# Diff concrete backend output only. No World IR placement semantics belong here.
func compare(old_world: ResolvedWorld, new_world: ResolvedWorld) -> Dictionary:
    var old_regions: Array = [] if old_world == null else old_world.regions
    var new_regions: Array = [] if new_world == null else new_world.regions
    var old_networks: Array = [] if old_world == null else old_world.networks
    var new_networks: Array = [] if new_world == null else new_world.networks
    var old_entities: Array = [] if old_world == null else old_world.entities
    var new_entities: Array = [] if new_world == null else new_world.entities
    var old_waters: Array = [] if old_world == null else old_world.waters
    var new_waters: Array = [] if new_world == null else new_world.waters
    var old_terrain: Resource = null if old_world == null else old_world.terrain
    var new_terrain: Resource = null if new_world == null else new_world.terrain
    var terrain_changed := not _terrain_equal(old_terrain, new_terrain)

    return {
        "regions": _diff_changed(
            _resource_entries(old_regions),
            _resource_entries(new_regions),
            Callable(self, "_region_equal")
        ),
        "networks": _diff_changed(
            _resource_entries(old_networks),
            _resource_entries(new_networks),
            Callable(self, "_network_equal")
        ),
        "entities": _diff_transformables(
            _resource_entries(old_entities),
            _resource_entries(new_entities),
            true
        ),
        "distribution_instances": _diff_transformables(
            _distribution_instance_entries(old_world),
            _distribution_instance_entries(new_world),
            true
        ),
        "decoration_instances": _diff_transformables(
            _decoration_instance_entries(old_world),
            _decoration_instance_entries(new_world),
            true
        ),
        "waters": _diff_changed(
            _resource_entries(old_waters),
            _resource_entries(new_waters),
            Callable(self, "_water_equal")
        ),
        "terrain": {
            "changed": terrain_changed,
            "unchanged": not terrain_changed,
            "old": old_terrain,
            "new": new_terrain,
        },
        "terrain_changed": terrain_changed,
    }

# Keep the old entry point as a compatibility alias, but it now returns the real
# object-level patch rather than collection counts.
func summarize(old_world: ResolvedWorld, new_world: ResolvedWorld) -> Dictionary:
    return compare(old_world, new_world)

func _diff_changed(old_entries: Array, new_entries: Array, equal: Callable) -> Dictionary:
    var result := _change_bucket()
    var old_by_id := _entries_by_id(old_entries)
    var new_by_id := _entries_by_id(new_entries)
    for object_id in _sorted_union_ids(old_by_id, new_by_id):
        if not old_by_id.has(object_id):
            result["added"].append(_record(object_id, {}, new_by_id[object_id]))
        elif not new_by_id.has(object_id):
            result["removed"].append(_record(object_id, old_by_id[object_id], {}))
        elif equal.call(old_by_id[object_id]["value"], new_by_id[object_id]["value"]):
            result["unchanged"].append(_record(object_id, old_by_id[object_id], new_by_id[object_id]))
        else:
            result["changed"].append(_record(object_id, old_by_id[object_id], new_by_id[object_id]))
    return result

func _diff_transformables(
    old_entries: Array,
    new_entries: Array,
    compare_semantic_type: bool
) -> Dictionary:
    var result := _transform_bucket()
    var old_by_id := _entries_by_id(old_entries)
    var new_by_id := _entries_by_id(new_entries)
    for object_id in _sorted_union_ids(old_by_id, new_by_id):
        if not old_by_id.has(object_id):
            result["added"].append(_record(object_id, {}, new_by_id[object_id]))
            continue
        if not new_by_id.has(object_id):
            result["removed"].append(_record(object_id, old_by_id[object_id], {}))
            continue
        var old_entry: Dictionary = old_by_id[object_id]
        var new_entry: Dictionary = new_by_id[object_id]
        var old_value: Variant = old_entry["value"]
        var new_value: Variant = new_entry["value"]
        var prototype_changed := _prototype_id(old_value) != _prototype_id(new_value)
        var semantic_changed := (
            compare_semantic_type
            and String(old_entry.get("semantic_type", ""))
                != String(new_entry.get("semantic_type", ""))
        )
        var record := _record(object_id, old_entry, new_entry)
        if prototype_changed or semantic_changed:
            result["replaced"].append(record)
        elif not _transform_equal(_transform(old_value), _transform(new_value)):
            result["moved"].append(record)
        else:
            result["unchanged"].append(record)
    return result

func _resource_entries(items: Array) -> Array:
    var result: Array = []
    for item in items:
        if item == null:
            continue
        var semantic_type := ""
        if item is ResolvedRegion or item is ResolvedNetwork or item is ResolvedEntity:
            semantic_type = String(item.semantic_type)
        result.append({
            "id": String(item.id),
            "semantic_type": semantic_type,
            "value": item,
        })
    return result

func _distribution_instance_entries(world: ResolvedWorld) -> Array:
    var result: Array = []
    if world == null:
        return result
    for distribution: ResolvedDistribution in world.distributions:
        for instance: Dictionary in distribution.instances:
            result.append({
                "id": String(instance.get("id", "")),
                "owner_id": distribution.id,
                "semantic_type": distribution.semantic_type,
                "value": instance,
            })
    return result

func _decoration_instance_entries(world: ResolvedWorld) -> Array:
    var result: Array = []
    if world == null:
        return result
    for decoration: ResolvedDecoration in world.decorations:
        for instance: Dictionary in decoration.instances:
            result.append({
                "id": String(instance.get("id", "")),
                "owner_id": decoration.id,
                "semantic_type": decoration.decoration_type,
                "value": instance,
            })
    return result

func _entries_by_id(entries: Array) -> Dictionary:
    var result := {}
    for entry: Dictionary in entries:
        result[String(entry.get("id", ""))] = entry
    return result

func _sorted_union_ids(a: Dictionary, b: Dictionary) -> Array[String]:
    var seen := {}
    for object_id in a.keys():
        seen[String(object_id)] = true
    for object_id in b.keys():
        seen[String(object_id)] = true
    var result: Array[String] = []
    for object_id in seen.keys():
        result.append(String(object_id))
    result.sort()
    return result

func _record(object_id: String, old_entry: Dictionary, new_entry: Dictionary) -> Dictionary:
    var owner_id := String(new_entry.get("owner_id", old_entry.get("owner_id", "")))
    var semantic_type := String(
        new_entry.get("semantic_type", old_entry.get("semantic_type", ""))
    )
    return {
        "id": object_id,
        "owner_id": owner_id,
        "semantic_type": semantic_type,
        "old": old_entry.get("value"),
        "new": new_entry.get("value"),
    }

func _change_bucket() -> Dictionary:
    return {"added": [], "removed": [], "changed": [], "unchanged": []}

func _transform_bucket() -> Dictionary:
    return {
        "added": [],
        "removed": [],
        "moved": [],
        "replaced": [],
        "unchanged": [],
    }

func _region_equal(old_region: ResolvedRegion, new_region: ResolvedRegion) -> bool:
    return (
        old_region.semantic_type == new_region.semantic_type
        and old_region.surface_kind == new_region.surface_kind
        and _vector2_array_equal(old_region.polygon, new_region.polygon)
    )

func _network_equal(old_network: ResolvedNetwork, new_network: ResolvedNetwork) -> bool:
    return (
        old_network.semantic_type == new_network.semantic_type
        and old_network.surface_kind == new_network.surface_kind
        and _float_equal(old_network.width, new_network.width)
        and _vector3_array_equal(old_network.curve_points, new_network.curve_points)
    )

func _water_equal(old_water: Resource, new_water: Resource) -> bool:
    return (
        String(old_water.source_region_id) == String(new_water.source_region_id)
        and _float_equal(float(old_water.sea_level), float(new_water.sea_level))
        and _vector2_equal(old_water.seaward_direction, new_water.seaward_direction)
        and _vector2_array_equal(old_water.shoreline, new_water.shoreline)
        and _vector2_array_equal(old_water.polygon, new_water.polygon)
    )

func _terrain_equal(old_terrain: Resource, new_terrain: Resource) -> bool:
    if old_terrain == null or new_terrain == null:
        return old_terrain == new_terrain
    if (
        old_terrain.grid_size != new_terrain.grid_size
        or not _rect_equal(old_terrain.world_bounds, new_terrain.world_bounds)
        or not _float_equal(old_terrain.road_surface_offset, new_terrain.road_surface_offset)
        or old_terrain.heights.size() != new_terrain.heights.size()
        or old_terrain.surface_masks.size() != new_terrain.surface_masks.size()
        or old_terrain.shore_wetness.size() != new_terrain.shore_wetness.size()
    ):
        return false
    for index in range(old_terrain.heights.size()):
        if not _float_equal(old_terrain.heights[index], new_terrain.heights[index]):
            return false
    for index in range(old_terrain.surface_masks.size()):
        if not _color_equal(old_terrain.surface_masks[index], new_terrain.surface_masks[index]):
            return false
    for index in range(old_terrain.shore_wetness.size()):
        if not _float_equal(old_terrain.shore_wetness[index], new_terrain.shore_wetness[index]):
            return false
    return true

func _prototype_id(value: Variant) -> String:
    if value is ResolvedEntity:
        return String(value.prototype_id)
    if typeof(value) == TYPE_DICTIONARY:
        return String((value as Dictionary).get("prototype_id", ""))
    return ""

func _transform(value: Variant) -> Transform3D:
    if value is ResolvedEntity:
        return value.transform
    if typeof(value) == TYPE_DICTIONARY:
        return (value as Dictionary).get("transform", Transform3D.IDENTITY)
    return Transform3D.IDENTITY

func _transform_equal(a: Transform3D, b: Transform3D) -> bool:
    return (
        _vector3_equal(a.origin, b.origin)
        and _vector3_equal(a.basis.x, b.basis.x)
        and _vector3_equal(a.basis.y, b.basis.y)
        and _vector3_equal(a.basis.z, b.basis.z)
    )

func _vector2_array_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
    if a.size() != b.size():
        return false
    for index in range(a.size()):
        if not _vector2_equal(a[index], b[index]):
            return false
    return true

func _vector3_array_equal(a: PackedVector3Array, b: PackedVector3Array) -> bool:
    if a.size() != b.size():
        return false
    for index in range(a.size()):
        if not _vector3_equal(a[index], b[index]):
            return false
    return true

func _rect_equal(a: Rect2, b: Rect2) -> bool:
    return _vector2_equal(a.position, b.position) and _vector2_equal(a.size, b.size)

func _color_equal(a: Color, b: Color) -> bool:
    return (
        _float_equal(a.r, b.r)
        and _float_equal(a.g, b.g)
        and _float_equal(a.b, b.b)
        and _float_equal(a.a, b.a)
    )

func _vector2_equal(a: Vector2, b: Vector2) -> bool:
    return a.distance_to(b) <= FLOAT_EPSILON

func _vector3_equal(a: Vector3, b: Vector3) -> bool:
    return a.distance_to(b) <= FLOAT_EPSILON

func _float_equal(a: float, b: float) -> bool:
    return absf(a - b) <= FLOAT_EPSILON
